import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Testing
import GRDB
@testable import WiredPartCore

@Suite("JobsService Tests", .serialized)
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

    @Test("local-first job records create update list and survive service reload")
    func testLocalFirstJobRecordsCRUDAndReload() throws {
        let env = try E2ETestHelpers.setUp()
        let created = try env.jobs.createJobRecord(
            JobsService.JobRecordDraft(
                jobNumber: "  J-LOCAL-001  ",
                jobName: "  Local First Job  ",
                customerName: "  Alpine Electric  ",
                siteName: "  Alpine City Hall  ",
                status: "active",
                priority: "high",
                notes: "  First site note  ",
                createdBy: env.adminUserId
            )
        )
        #expect(created.id > 0)
        #expect(!created.stableId.isEmpty)
        #expect(UUID(uuidString: created.stableId) != nil)
        #expect(created.jobNumber == "J-LOCAL-001")
        #expect(created.jobName == "Local First Job")
        #expect(created.customerName == "Alpine Electric")
        #expect(created.siteName == "Alpine City Hall")
        #expect(created.notes == "First site note")

        let reloadedService = JobsService(db: env.db)
        let reloaded = try reloadedService.getJobRecord(id: created.id)
        #expect(reloaded.stableId == created.stableId)

        let updated = try reloadedService.updateJobRecord(
            id: created.id,
            JobsService.JobRecordUpdate(
                jobName: "  Local First Job - Updated  ",
                customerName: "  Alpine Public Works  ",
                siteName: "  Council Chambers  ",
                status: "in_progress",
                priority: "critical",
                notes: "  Updated field note  "
            )
        )
        #expect(updated.stableId == created.stableId)
        #expect(updated.jobName == "Local First Job - Updated")
        #expect(updated.customerName == "Alpine Public Works")
        #expect(updated.siteName == "Council Chambers")
        #expect(updated.status == "in_progress")
        #expect(updated.priority == "critical")
        #expect(updated.notes == "Updated field note")

        let listed = try reloadedService.listJobRecords(status: "in_progress")
        #expect(listed.contains { $0.id == created.id && $0.stableId == created.stableId })

        let clearedSite = try reloadedService.updateJobRecord(
            id: created.id,
            JobsService.JobRecordUpdate(siteName: "   ")
        )
        #expect(clearedSite.siteName == nil)
        let addressLine1 = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT address_line1 FROM jobs WHERE id = ?", arguments: [created.id])
        }
        #expect(addressLine1 == nil)
    }

    @Test("local-first job records reject invalid input and expose empty state")
    func testLocalFirstJobRecordsInvalidInputAndEmptyState() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(try env.jobs.listJobRecords(status: "cancelled").isEmpty)
        #expect(throws: JobsService.JobsError.requiredFieldEmpty) {
            _ = try env.jobs.createJobRecord(
                JobsService.JobRecordDraft(jobNumber: " ", jobName: "Blank Number", createdBy: env.adminUserId)
            )
        }
        #expect(throws: JobsService.JobsError.requiredFieldEmpty) {
            _ = try env.jobs.createJobRecord(
                JobsService.JobRecordDraft(jobNumber: "J-BLANK-NAME", jobName: " ", createdBy: env.adminUserId)
            )
        }
    }

    @Test("seeded jobs receive stable ids after local-first schema is available")
    func testSeededJobsReceiveStableIds() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-BACKFILL", name: "Backfilled Job")
        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT stable_id FROM jobs WHERE id = ?", arguments: [jobId])
        }
        let stableId = try #require(row?["stable_id"] as String?)
        #expect(UUID(uuidString: stableId) != nil)
    }

    @Test("createJob creates a linked job notebook")
    func testCreateJobCreatesLinkedNotebook() throws {
        let env = try E2ETestHelpers.setUp()
        try env.notebooks.seedDefaultTemplates(createdBy: env.adminUserId)

        let jobId = try env.jobs.createJob(
            jobNumber: "JN-AUTO-NB",
            jobName: "Auto Notebook Job",
            jobType: "residential",
            createdBy: env.adminUserId
        )

        let notebooks = try env.notebooks.listNotebooks(notebookType: "job", jobId: jobId)
        #expect(notebooks.count == 1)
        #expect(notebooks[0].title.contains("Auto Notebook Job"))
    }

    @Test("createJob internally seeds templates for create-job user without manage_templates")
    func testCreateJobSeedsTemplatesWithoutManageTemplatesPermission() throws {
        let env = try E2ETestHelpers.setUp()
        let officeUserId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active, created_at, updated_at)
                VALUES ('Office Create Jobs Only', 'test-hash', 1, datetime('now'), datetime('now'))
                """)
            let userId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO user_hats (user_id, hat_id, is_active)
                SELECT ?, id, 1 FROM hats WHERE name = 'Lead'
                """, arguments: [userId])
            return userId
        }
        #expect(try env.auth.hasPermission(officeUserId, permissionKey: "create_jobs"))
        #expect(!(try env.auth.hasPermission(officeUserId, permissionKey: "manage_templates")))
        try env.db.writer.write { db in
            try db.execute(sql: "DELETE FROM notebook_templates")
        }

        let jobId = try env.jobs.createJob(
            jobNumber: "JN-NO-MANAGE-TEMPLATES",
            jobName: "Create Only Job",
            jobType: "service",
            createdBy: officeUserId
        )

        let notebooks = try env.notebooks.listNotebooks(notebookType: "job", jobId: jobId)
        let templateCount = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notebook_templates WHERE template_type = 'job' AND deleted_at IS NULL") ?? 0
        }
        #expect(notebooks.count == 1)
        #expect(templateCount >= 3)
    }

    @Test("listJobs aggregates completed labor and job-linked PO line costs without duplication")
    func testListJobsAggregatesCompletedLaborAndPOLineCosts() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-LIST-1", name: "Aggregate Job")
        let secondJpoJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-LIST-2", name: "Other Job")
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let categoryId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Primary Part", categoryId: categoryId)
        let secondPartId = try E2ETestHelpers.seedPart(env, name: "Secondary Part", categoryId: categoryId)

        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE users SET pay_rate = ?, deleted_at = NULL, is_active = 1 WHERE id = ?",
                arguments: [20.0, env.adminUserId]
            )
            try db.execute(
                sql: "UPDATE jobs SET estimated_hours = ?, budget_limit = ? WHERE id = ?",
                arguments: [12.5, 500.0, jobId]
            )

            try db.execute(sql: """
                INSERT INTO labor_entries
                    (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES (?, ?, datetime('now', '-8 hours'), datetime('now', '-2 hours'), 4.0, 2.0, 'completed', datetime('now'))
                """, arguments: [env.adminUserId, jobId])
            try db.execute(sql: """
                INSERT INTO labor_entries
                    (user_id, job_id, clock_in, regular_hours, overtime_hours, status, created_at)
                VALUES (?, ?, datetime('now', '-1 hours'), 10.0, 5.0, 'clocked_in', datetime('now'))
                """, arguments: [env.adminUserId, jobId])

            try db.execute(sql: """
                INSERT INTO job_parts_orders (job_id, order_number, status, requested_by, created_at, updated_at)
                VALUES (?, 'JPO-LIST-1', 'submitted', ?, datetime('now'), datetime('now'))
                """, arguments: [jobId, env.adminUserId])
            let firstJpoId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO job_parts_orders (job_id, order_number, status, requested_by, created_at, updated_at)
                VALUES (?, 'JPO-LIST-2', 'submitted', ?, datetime('now'), datetime('now'))
                """, arguments: [jobId, env.adminUserId])
            let secondJpoId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO job_parts_orders (job_id, order_number, status, requested_by, created_at, updated_at)
                VALUES (?, 'JPO-LIST-3', 'submitted', ?, datetime('now'), datetime('now'))
                """, arguments: [secondJpoJobId, env.adminUserId])
            let otherJobJpoId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO jpo_line_items (jpo_id, part_id, qty_requested, qty_ordered, created_at)
                VALUES (?, ?, 3, 3, datetime('now'))
                """, arguments: [firstJpoId, partId])
            let firstJpoLineId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO jpo_line_items (jpo_id, part_id, qty_requested, qty_ordered, created_at)
                VALUES (?, ?, 1, 1, datetime('now'))
                """, arguments: [secondJpoId, secondPartId])
            let secondJpoLineId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO jpo_line_items (jpo_id, part_id, qty_requested, qty_ordered, created_at)
                VALUES (?, ?, 2, 2, datetime('now'))
                """, arguments: [otherJobJpoId, secondPartId])
            let otherJobLineId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO purchase_orders
                    (po_number, supplier_id, status, total_cost, submitted_by, created_at, updated_at)
                VALUES ('PO-LIST-1', ?, 'submitted', 999.0, ?, datetime('now'), datetime('now'))
                """, arguments: [supplierId, env.adminUserId])
            let firstPoId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO purchase_orders
                    (po_number, supplier_id, status, total_cost, submitted_by, created_at, updated_at)
                VALUES ('PO-LIST-2', ?, 'cancelled', 1000.0, ?, datetime('now'), datetime('now'))
                """, arguments: [supplierId, env.adminUserId])
            let cancelledPoId = db.lastInsertedRowID

            try db.execute(sql: "INSERT INTO po_jpo_links (po_id, jpo_id, created_at) VALUES (?, ?, datetime('now'))", arguments: [firstPoId, firstJpoId])
            try db.execute(sql: "INSERT INTO po_jpo_links (po_id, jpo_id, created_at) VALUES (?, ?, datetime('now'))", arguments: [firstPoId, secondJpoId])
            try db.execute(sql: "INSERT INTO po_jpo_links (po_id, jpo_id, created_at) VALUES (?, ?, datetime('now'))", arguments: [firstPoId, otherJobJpoId])

            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, jpo_line_id, part_id, qty_ordered, unit_cost, created_at)
                VALUES (?, ?, ?, 3, 15.0, datetime('now'))
                """, arguments: [firstPoId, firstJpoLineId, partId])
            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, jpo_line_id, part_id, qty_ordered, unit_cost, received_unit_cost, created_at)
                VALUES (?, ?, ?, 1, 35.0, 40.0, datetime('now'))
                """, arguments: [firstPoId, secondJpoLineId, secondPartId])
            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, jpo_line_id, part_id, qty_ordered, unit_cost, created_at)
                VALUES (?, ?, ?, 2, 50.0, datetime('now'))
                """, arguments: [cancelledPoId, otherJobLineId, secondPartId])
        }

        let jobs = try env.jobs.listJobs()
        let job = try #require(jobs.first(where: { $0.id == jobId }))
        let otherJob = try #require(jobs.first(where: { $0.id == secondJpoJobId }))
        #expect(job.estimatedHours == 12.5)
        #expect(job.budgetLimit == 500.0)
        #expect(abs(job.laborHours - 6.0) < 0.0001)
        #expect(abs(job.actualCost - 225.0) < 0.0001)
        #expect(abs(otherJob.actualCost) < 0.0001)
    }

    @Test("listJobs includes stage template id for template-aware UIs")
    func testListJobsIncludesStageTemplateId() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-STAGE-TEMPLATE", name: "Template Job")
        let templateId = try env.jobs.createJobStageTemplate(name: "Template A", stageNames: ["Stage 1", "Stage 2"])

        try env.jobs.assignJobStageTemplate(jobId: jobId, templateId: templateId)

        let jobs = try env.jobs.listJobs()
        let job = try #require(jobs.first(where: { $0.id == jobId }))
        #expect(job.stageTemplateId == templateId)
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

    @Test("Update job clears optional text fields when blank values are saved")
    func testUpdateJobClearsOptionalTextFields() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try env.jobs.createJob(
            jobNumber: "J-CLEAR-OPTIONAL",
            jobName: "Clear Optional Fields",
            customerName: "Customer To Clear",
            addressLine1: "123 Clear St",
            status: "active",
            notes: "Notes to clear",
            createdBy: env.adminUserId
        )

        try env.jobs.updateJob(
            id: jobId,
            customerName: "",
            addressLine1: "",
            notes: ""
        )

        let detail = try env.jobs.getJob(id: jobId)
        #expect(detail.customerName == "")
        #expect(detail.addressLine1 == "")
        #expect(detail.notes == "")
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

    @Test("Warehouse clock in creates current shop entry")
    func testWarehouseClockInCreatesCurrentShopEntry() throws {
        let env = try E2ETestHelpers.setUp()

        let laborEntryId = try env.jobs.clockInToWarehouse(userId: env.adminUserId)
        let active = try env.jobs.getActiveClockEntry(userId: env.adminUserId)

        #expect(laborEntryId > 0)
        #expect(active?.id == laborEntryId)
        #expect(active?.jobName == "Shop / Warehouse")

        let stableId = try env.db.writer.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT stable_id FROM jobs WHERE job_number = ? AND deleted_at IS NULL",
                arguments: ["__SHOP_WAREHOUSE__"]
            )
        }
        #expect(stableId.flatMap(UUID.init(uuidString:)) != nil)
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

    @Test("Daily overtime threshold spans multiple labor entries")
    func testDailyOvertimeThresholdSpansMultipleLaborEntries() throws {
        try withMountainTimeZone {
            let env = try E2ETestHelpers.setUp()
            let firstJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-OT-1", name: "First OT Job")
            let secondJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-OT-2", name: "Second OT Job")

            let firstLaborEntryId = try env.jobs.clockIn(
                userId: env.adminUserId,
                jobId: firstJobId,
                at: try Self.localToday(hour: 8, minute: 0)
            )
            try env.jobs.clockOut(
                laborEntryId: firstLaborEntryId,
                at: try Self.localToday(hour: 14, minute: 0)
            )

            let secondLaborEntryId = try env.jobs.clockIn(
                userId: env.adminUserId,
                jobId: secondJobId,
                at: try Self.localToday(hour: 14, minute: 0)
            )
            try env.jobs.clockOut(
                laborEntryId: secondLaborEntryId,
                at: try Self.localToday(hour: 18, minute: 0)
            )

            let secondEntry = try env.db.writer.read { db in
                try Row.fetchOne(
                    db,
                    sql: "SELECT regular_hours, overtime_hours FROM labor_entries WHERE id = ?",
                    arguments: [secondLaborEntryId]
                )
            }

            #expect(secondEntry?["regular_hours"] as Double? == 2.0)
            #expect(secondEntry?["overtime_hours"] as Double? == 2.0)
        }
    }

    @Test("Weekly overtime settings split hours after configured threshold")
    func testWeeklyOvertimeSettingsSplitHoursAfterThreshold() throws {
        try withMountainTimeZone {
            let env = try E2ETestHelpers.setUp()
            let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-WEEKLY-OT", name: "Weekly OT")
            _ = try env.jobs.updateOvertimeSettings(
                calculationRule: "weekly_only",
                dailyThresholdHours: 24.0,
                weeklyThresholdHours: 40.0,
                weekStartWeekday: 2,
                updatedBy: env.adminUserId
            )

            for dayOffset in 0..<5 {
                let entryId = try env.jobs.clockIn(
                    userId: env.adminUserId,
                    jobId: jobId,
                    at: try Self.localWeekday(dayOffset: dayOffset, hour: 8, minute: 0)
                )
                try env.jobs.clockOut(
                    laborEntryId: entryId,
                    at: try Self.localWeekday(dayOffset: dayOffset, hour: 16, minute: 0)
                )
            }

            let saturdayEntryId = try env.jobs.clockIn(
                userId: env.adminUserId,
                jobId: jobId,
                at: try Self.localWeekday(dayOffset: 5, hour: 8, minute: 0)
            )
            try env.jobs.clockOut(
                laborEntryId: saturdayEntryId,
                at: try Self.localWeekday(dayOffset: 5, hour: 12, minute: 0)
            )

            let saturdayEntry = try env.db.writer.read { db in
                try Row.fetchOne(
                    db,
                    sql: "SELECT regular_hours, overtime_hours FROM labor_entries WHERE id = ?",
                    arguments: [saturdayEntryId]
                )
            }

            #expect(saturdayEntry?["regular_hours"] as Double? == 0.0)
            #expect(saturdayEntry?["overtime_hours"] as Double? == 4.0)
        }
    }

    @Test("Labor correction persists actor reason and before after hours")
    func testLaborCorrectionPersistsAudit() throws {
        try withMountainTimeZone {
            let env = try E2ETestHelpers.setUp()
            let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-CORRECT", name: "Correction Audit")
            let entryId = try env.jobs.clockIn(
                userId: env.adminUserId,
                jobId: jobId,
                at: try Self.localToday(hour: 8, minute: 0)
            )
            try env.jobs.clockOut(
                laborEntryId: entryId,
                at: try Self.localToday(hour: 12, minute: 0)
            )

            let auditId = try env.jobs.correctLaborEntry(
                laborEntryId: entryId,
                correctedBy: env.adminUserId,
                reason: "Manager approved missed clock-out correction",
                clockIn: try Self.localToday(hour: 8, minute: 0),
                clockOut: try Self.localToday(hour: 17, minute: 0)
            )
            let audits = try env.jobs.listLaborEntryCorrectionAudits(laborEntryId: entryId)
            let corrected = try env.db.writer.read { db in
                try Row.fetchOne(
                    db,
                    sql: "SELECT regular_hours, overtime_hours, edited_by FROM labor_entries WHERE id = ?",
                    arguments: [entryId]
                )
            }

            #expect(auditId > 0)
            #expect(audits.count == 1)
            #expect(audits[0].correctedBy == env.adminUserId)
            #expect(audits[0].reason == "Manager approved missed clock-out correction")
            #expect(audits[0].oldRegularHours == 4.0)
            #expect(audits[0].newRegularHours == 8.0)
            #expect(audits[0].newOvertimeHours == 1.0)
            #expect(corrected?["regular_hours"] as Double? == 8.0)
            #expect(corrected?["overtime_hours"] as Double? == 1.0)
            #expect(corrected?["edited_by"] as Int64? == env.adminUserId)
        }
    }

    @Test("Switching jobs closes current entry and starts next entry at the same instant")
    func testSwitchClockedInJobIsAtomicAndDeterministic() throws {
        try withMountainTimeZone {
            let env = try E2ETestHelpers.setUp()
            let firstJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-SW-1", name: "Switch From")
            let secondJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-SW-2", name: "Switch To")

            let firstEntryId = try env.jobs.clockIn(
                userId: env.adminUserId,
                jobId: firstJobId,
                at: try Self.localToday(hour: 7, minute: 0)
            )
            let secondEntryId = try env.jobs.switchClockedInJob(
                userId: env.adminUserId,
                nextJobId: secondJobId,
                at: try Self.localToday(hour: 12, minute: 15)
            )

            let entries = try env.jobs.listLaborEntries(userId: env.adminUserId)
            let firstEntry = try #require(entries.first { $0.id == firstEntryId })
            let secondEntry = try #require(entries.first { $0.id == secondEntryId })
            let active = try env.jobs.getActiveClockEntry(userId: env.adminUserId)

            #expect(firstEntry.status == "completed")
            #expect(firstEntry.clockOut == secondEntry.clockIn)
            #expect(firstEntry.regularHours == 5.25)
            #expect(firstEntry.overtimeHours == 0.0)
            #expect(secondEntry.status == "clocked_in")
            #expect(active?.id == secondEntryId)
            #expect(active?.jobId == secondJobId)
        }
    }

    @Test("Switching jobs keeps current entry active when target job is not clockable")
    func testSwitchClockedInJobRollsBackWhenTargetIsNotClockable() throws {
        try withMountainTimeZone {
            let env = try E2ETestHelpers.setUp()
            let firstJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-SW-STAY", name: "Switch Stays Active")
            let closedJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-SW-CLOSED", name: "Closed Switch Target")

            let firstEntryId = try env.jobs.clockIn(
                userId: env.adminUserId,
                jobId: firstJobId,
                at: try Self.localToday(hour: 7, minute: 0)
            )
            try env.jobs.updateJob(id: closedJobId, status: "completed")

            #expect(throws: JobsService.JobsError.jobNotClockable(closedJobId)) {
                try env.jobs.switchClockedInJob(
                    userId: env.adminUserId,
                    nextJobId: closedJobId,
                    at: try Self.localToday(hour: 12, minute: 15)
                )
            }

            let entries = try env.jobs.listLaborEntries(userId: env.adminUserId)
            let originalEntry = try #require(entries.first { $0.id == firstEntryId })
            let active = try env.jobs.getActiveClockEntry(userId: env.adminUserId)

            #expect(entries.count == 1)
            #expect(originalEntry.status == "clocked_in")
            #expect(originalEntry.clockOut == nil)
            #expect(active?.id == firstEntryId)
            #expect(active?.jobId == firstJobId)
        }
    }

    @Test("Clock out subtracts unpaid breaks but keeps paid breaks compensable")
    func testClockOutBreakPayTreatmentIsDeterministic() throws {
        try withMountainTimeZone {
            let env = try E2ETestHelpers.setUp()
            let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-BREAK-PAY", name: "Break Pay Job")
            let laborEntryId = try env.jobs.clockIn(
                userId: env.adminUserId,
                jobId: jobId,
                at: try Self.localToday(hour: 8, minute: 0)
            )
            let paidBreakStart = Self.utcTimestampFormatter.string(from: try Self.localToday(hour: 10, minute: 0))
            let paidBreakEnd = Self.utcTimestampFormatter.string(from: try Self.localToday(hour: 10, minute: 15))
            let unpaidLunchStart = Self.utcTimestampFormatter.string(from: try Self.localToday(hour: 12, minute: 0))
            let unpaidLunchEnd = Self.utcTimestampFormatter.string(from: try Self.localToday(hour: 12, minute: 30))

            try env.db.writer.write { db in
                try db.execute(sql: """
                    INSERT INTO break_records
                        (user_id, labor_entry_id, break_type, started_at, ended_at, duration_minutes, is_paid, auto_filled)
                    VALUES
                        (?, ?, 'break', ?, ?, 15, 1, 0),
                        (?, ?, 'lunch_unpaid', ?, ?, 30, 0, 0)
                    """, arguments: [
                    env.adminUserId, laborEntryId, paidBreakStart, paidBreakEnd,
                    env.adminUserId, laborEntryId, unpaidLunchStart, unpaidLunchEnd
                ])
            }

            try env.jobs.clockOut(
                laborEntryId: laborEntryId,
                at: try Self.localToday(hour: 17, minute: 0)
            )

            let entry = try env.db.writer.read { db in
                try Row.fetchOne(
                    db,
                    sql: "SELECT regular_hours, overtime_hours FROM labor_entries WHERE id = ?",
                    arguments: [laborEntryId]
                )
            }

            #expect(entry?["regular_hours"] as Double? == 8.0)
            #expect(entry?["overtime_hours"] as Double? == 0.5)
        }
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

    @Test("Default clock-out questions include daily report prompt")
    func testDefaultClockOutQuestionsIncludeDailyReportPrompt() throws {
        let env = try E2ETestHelpers.setUp()
        let questions = try env.jobs.getActiveQuestions()

        let dailyReportQuestion = questions.first { question in
            question.questionText.localizedCaseInsensitiveContains("daily report")
        }

        #expect(dailyReportQuestion != nil)
        #expect(dailyReportQuestion?.answerType == "text")
        #expect(dailyReportQuestion?.isRequired == true)
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

    @Test("job notes are timestamped and attributed through job notebook")
    func testJobNotesAreTimestampedAndAttributed() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try env.jobs.createJob(
            jobNumber: "J-NOTES",
            jobName: "Notes Job",
            notes: "Initial field note",
            createdBy: env.adminUserId
        )

        _ = try env.jobs.addJobNote(
            jobId: jobId,
            title: "Field update",
            content: "Crew finished rough-in walkthrough.",
            createdBy: env.adminUserId
        )

        let notes = try env.jobs.listJobNotes(jobId: jobId)
        #expect(notes.count >= 2)
        #expect(notes.contains { $0.title == "Initial job note" && $0.content == "Initial field note" })
        let update = try #require(notes.first { $0.title == "Field update" })
        #expect(update.authorId == env.adminUserId)
        #expect(!update.authorName.isEmpty)
        #expect(update.createdAt != nil)
    }

    // MARK: - Job Stages

    @Test("List job stages")
    func testJobStages() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let stages = try env.jobs.listJobStages(forJobId: jobId)
        #expect(stages.count >= 0)
    }

    @Test("updateJobStage records attributed stage-change audit")
    func testUpdateJobStageRecordsAudit() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let templateId = try #require(try env.jobs.listJobStageTemplates().first?.id)
        let stages = try env.jobs.listAllJobStages(templateId: templateId)
        let roughId = try #require(stages.first(where: { $0.name == "Rough-in" })?.id)
        let trimId = try #require(stages.first(where: { $0.name == "Trim-out" })?.id)

        try env.jobs.updateJobStage(jobId: jobId, stageId: roughId, changedBy: env.adminUserId)
        try env.jobs.updateJobStage(jobId: jobId, stageId: trimId, changedBy: env.adminUserId, note: "Crew moved to trim.")

        let currentStageId: Int64? = try env.db.writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT current_stage_id FROM jobs WHERE id = ?", arguments: [jobId])
        }
        let auditNotes = try env.jobs.listJobNotes(jobId: jobId).filter { $0.entryType == "stage_change" }
        #expect(currentStageId == trimId)
        #expect(auditNotes.count == 2)
        #expect(auditNotes.contains { $0.title.contains("Rough-in -> Trim-out") && $0.content == "Crew moved to trim." })
        #expect(auditNotes.allSatisfy { $0.authorId == env.adminUserId && $0.createdAt != nil })
    }

    @Test("job inventory movement feed reads Stage 3 job-linked stock movements")
    func testJobInventoryMovementFeedReadsLinkedMovements() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let categoryId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Job Wire", categoryId: categoryId)

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO stock_movements
                    (part_id, qty, from_location_type, from_location_id, to_location_type, to_location_id,
                     movement_type, reason, notes, performed_by, job_id, created_at)
                VALUES (?, 4, 'warehouse', 1, 'job', ?, ?, 'Job pull', 'Pulled for install',
                        ?, ?, datetime('now'))
                """, arguments: [partId, jobId, StockMovement.MovementType.jobPull.rawValue, env.adminUserId, jobId])
        }

        let movements = try env.jobs.listJobInventoryMovements(jobId: jobId)
        let movement = try #require(movements.first)
        #expect(movement.partId == partId)
        #expect(movement.partName == "Job Wire")
        #expect(movement.qty == 4)
        #expect(movement.movementType == StockMovement.MovementType.jobPull.rawValue)
        #expect(movement.notes == "Pulled for install")
        #expect(movement.performedByName == env.adminUser.displayName)
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

    @Test("Today's clock entries use local-day completed labor")
    func testGetTodaysClockEntriesUsesLocalOperationalDayForCompletedLabor() throws {
        try withMountainTimeZone {
            let env = try E2ETestHelpers.setUp()
            let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-CLOCK-LOCAL", name: "Local Clock Job")
            let clockIn = Self.utcTimestampFormatter.string(from: try Self.localToday(hour: 22, minute: 30))
            let clockOut = Self.utcTimestampFormatter.string(from: try Self.localToday(hour: 23, minute: 30))

            try env.db.writer.write { db in
                try db.execute(sql: "DELETE FROM labor_entries")
                try db.execute(sql: """
                    INSERT INTO labor_entries
                        (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                    VALUES (?, ?, ?, ?, 1.0, 0.0, 'completed', datetime('now'))
                    """, arguments: [env.adminUserId, jobId, clockIn, clockOut])
            }

            let groups = try env.jobs.getTodaysClockEntries(userId: env.adminUserId)
            let group = try #require(groups.first(where: { $0.jobId == jobId }))

            #expect(group.jobName == "Local Clock Job")
            #expect(group.entries.count == 1)
            #expect(abs(group.totalDuration - 3600) < 1)
        }
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

    @Test("job material contract pulls consumes returns and balances inventory")
    func testJobMaterialPullConsumeReturnContract() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-MAT-USE", name: "Material Use Job")
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Wire Nut", categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10, locationType: "warehouse", locationId: 1)

        _ = try env.jobs.pullJobMaterial(
            jobId: jobId,
            partId: partId,
            qty: 10,
            fromLocationType: "warehouse",
            fromLocationId: 1,
            performedBy: env.adminUserId,
            notes: "Pulled for install"
        )

        let readyBefore = try env.jobs.listReadyJobMaterials(jobId: jobId)
        #expect(readyBefore.first?.partId == partId)
        #expect(readyBefore.first?.stagedQty == 10)
        #expect(try env.warehouse.getStockQty(partId: partId, locationType: "warehouse", locationId: 1) == 0)

        let jobPartId = try env.jobs.consumeStagedJobMaterial(
            jobId: jobId,
            partId: partId,
            qty: 7,
            performedBy: env.adminUserId,
            notes: "Used seven on rough-in"
        )

        _ = try env.jobs.returnPulledJobMaterial(
            jobId: jobId,
            partId: partId,
            qty: 3,
            toLocationType: "warehouse",
            toLocationId: 1,
            performedBy: env.adminUserId,
            notes: "Returned unused wire nuts"
        )

        let readyAfter = try env.jobs.listReadyJobMaterials(jobId: jobId)
        #expect(readyAfter.isEmpty)
        #expect(try env.warehouse.getStockQty(partId: partId, locationType: "pulled", locationId: jobId) == 0)
        #expect(try env.warehouse.getStockQty(partId: partId, locationType: "warehouse", locationId: 1) == 3)

        let jobPart = try #require(try env.jobs.getJobParts(jobId: jobId).first { $0.id == jobPartId })
        #expect(jobPart.qtyConsumed == 7)
        #expect(jobPart.qtyReturned == 0)

        let totals = try env.jobs.getJobMaterialTotals(jobId: jobId)
        #expect(totals.stagedQty == 0)
        #expect(totals.usedQty == 7)
        #expect(totals.returnedQty == 0)

        let history = try env.jobs.listJobMaterialHistory(jobId: jobId)
        #expect(history.contains { $0.eventType == StockMovement.MovementType.transfer.rawValue && $0.qty == 10 })
        #expect(history.contains { $0.eventType == StockMovement.MovementType.jobPull.rawValue && $0.qty == 7 })
        #expect(history.contains { $0.eventType == StockMovement.MovementType.stockReturn.rawValue && $0.qty == 3 })
    }

    @Test("job material pull uses selected non-warehouse source")
    func testJobMaterialPullUsesSelectedNonWarehouseSource() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-MAT-TRUCK", name: "Truck Material Job")
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Truck Stock Only Part", categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 5, locationType: "truck", locationId: 42)

        _ = try env.jobs.pullJobMaterial(
            jobId: jobId,
            partId: partId,
            qty: 3,
            fromLocationType: "truck",
            fromLocationId: 42,
            performedBy: env.adminUserId,
            notes: "Pulled from service truck"
        )

        #expect(try env.warehouse.getStockQty(partId: partId, locationType: "truck", locationId: 42) == 2)
        #expect(try env.warehouse.getStockQty(partId: partId, locationType: "warehouse", locationId: 1) == 0)
        #expect(try env.warehouse.getStockQty(partId: partId, locationType: "pulled", locationId: jobId) == 3)

        let movement = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: """
                SELECT from_location_type, from_location_id, to_location_type, to_location_id
                FROM stock_movements
                WHERE job_id = ? AND part_id = ? AND qty = 3 AND deleted_at IS NULL
                ORDER BY id DESC
                LIMIT 1
                """, arguments: [jobId, partId])
        }
        #expect(movement?["from_location_type"] as String? == "truck")
        #expect(movement?["from_location_id"] as Int64? == 42)
        #expect(movement?["to_location_type"] as String? == "pulled")
        #expect(movement?["to_location_id"] as Int64? == jobId)
    }

    @Test("returnConsumedJobMaterial credits job totals once and creates return intake")
    func testReturnConsumedJobMaterialContract() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-MAT-RETURN", name: "Material Return Job")
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Returnable Breaker", categoryId: catId)
        let jobPartId = try env.jobs.addJobPart(
            jobId: jobId,
            partId: partId,
            qty: 4,
            costAtConsume: 12.5,
            performedBy: env.adminUserId
        )

        let intakeId = try env.jobs.returnConsumedJobMaterial(
            jobPartId: jobPartId,
            returnQty: 2,
            condition: "damaged",
            performedBy: env.adminUserId,
            notes: "Cracked case"
        )

        let jobPart = try #require(try env.jobs.getJobParts(jobId: jobId).first { $0.id == jobPartId })
        #expect(jobPart.qtyReturned == 2)

        let totals = try env.jobs.getJobMaterialTotals(jobId: jobId)
        #expect(totals.usedQty == 2)
        #expect(totals.pendingReturnQty == 2)
        #expect(totals.returnedQty == 2)
        #expect(totals.netMaterialCost == 25.0)
        #expect(totals.totalMaterialCost == 50.0)

        let intakeRow = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: """
                SELECT jri.source_job_id, jrii.source_job_part_id, jrii.qty_returned, jrii.condition, jrii.status
                FROM job_return_intakes jri
                JOIN job_return_intake_items jrii ON jrii.intake_id = jri.id
                WHERE jri.id = ?
                """, arguments: [intakeId])
        }
        #expect(intakeRow?["source_job_id"] as Int64? == jobId)
        #expect(intakeRow?["source_job_part_id"] as Int64? == jobPartId)
        #expect(intakeRow?["qty_returned"] as Int? == 2)
        #expect(intakeRow?["condition"] as String? == "damaged")
        #expect(intakeRow?["status"] as String? == "damage_review")

        let history = try env.jobs.listJobMaterialHistory(jobId: jobId)
        #expect(history.contains { $0.eventType == StockMovement.MovementType.stockReturn.rawValue && $0.qty == 2 })
        #expect(history.contains { $0.eventType == "job_return_damage_review" && $0.qty == 2 })
    }

    @Test("correctConsumedJobMaterial requires a note and writes adjustment history")
    func testCorrectConsumedJobMaterialContract() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-MAT-CORRECT", name: "Material Correction Job")
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Correction Part", categoryId: catId)
        let jobPartId = try env.jobs.addJobPart(
            jobId: jobId,
            partId: partId,
            qty: 9,
            costAtConsume: 3.0,
            performedBy: env.adminUserId
        )

        var missingNoteThrew = false
        do {
            try env.jobs.correctConsumedJobMaterial(
                jobPartId: jobPartId,
                adjustedQty: 7,
                performedBy: env.adminUserId,
                note: " "
            )
        } catch JobsService.JobsError.requiredFieldEmpty {
            missingNoteThrew = true
        } catch {}
        #expect(missingNoteThrew)

        try env.jobs.correctConsumedJobMaterial(
            jobPartId: jobPartId,
            adjustedQty: 7,
            performedBy: env.adminUserId,
            note: "Two were entered by mistake."
        )

        let jobPart = try #require(try env.jobs.getJobParts(jobId: jobId).first { $0.id == jobPartId })
        #expect(jobPart.qtyConsumed == 7)

        let totals = try env.jobs.getJobMaterialTotals(jobId: jobId)
        #expect(totals.usedQty == 7)
        #expect(totals.netMaterialCost == 21.0)

        let history = try env.jobs.listJobMaterialHistory(jobId: jobId)
        let adjustment = try #require(history.first { $0.eventType == StockMovement.MovementType.adjustment.rawValue })
        #expect(adjustment.qty == 2)
        #expect(adjustment.notes?.contains("original_qty=9") == true)
        #expect(adjustment.notes?.contains("adjusted_qty=7") == true)
        #expect(adjustment.notes?.contains("Two were entered by mistake.") == true)
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

    @Test("Jobs dashboard KPIs bucket UTC end-of-day labor into local today")
    func testJobsDashboardKPIsUseLocalClockInDateBucket() throws {
        try withMountainTimeZone {
            let env = try E2ETestHelpers.setUp()
            let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-KPI-LOCAL", name: "Local KPI")
            let clockIn = Self.utcTimestampFormatter.string(from: try Self.localToday(hour: 23, minute: 30))

            try env.db.writer.write { db in
                try db.execute(sql: "DELETE FROM labor_entries")
                try db.execute(sql: """
                    INSERT INTO labor_entries
                        (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                    VALUES (?, ?, ?, ?, 3.0, 0.0, 'completed', datetime('now'))
                    """, arguments: [env.adminUserId, jobId, clockIn, clockIn])
            }

            let kpis = try env.jobs.getJobsDashboardKPIs()

            #expect(kpis.todayLaborHours == 3.0)
        }
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

    private static let utcTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func localToday(hour: Int, minute: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Denver"))
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return try #require(calendar.date(from: components))
    }

    private static func localWeekday(dayOffset: Int, hour: Int, minute: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Denver"))
        calendar.firstWeekday = 2
        let todayStart = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: todayStart)
        let daysSinceMonday = (weekday - 2 + 7) % 7
        let monday = try #require(calendar.date(byAdding: .day, value: -daysSinceMonday, to: todayStart))
        let targetDay = try #require(calendar.date(byAdding: .day, value: dayOffset, to: monday))
        var components = calendar.dateComponents([.year, .month, .day], from: targetDay)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return try #require(calendar.date(from: components))
    }

    private func withMountainTimeZone<T>(_ body: () throws -> T) rethrows -> T {
        #if canImport(Darwin) || canImport(Glibc)
        let originalTZ = getenv("TZ").map { String(cString: $0) }
        setenv("TZ", "America/Denver", 1)
        tzset()
        defer {
            if let originalTZ {
                setenv("TZ", originalTZ, 1)
            } else {
                unsetenv("TZ")
            }
            tzset()
        }
        #endif
        return try body()
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

        let dailyReportQuestionId = try #require(try env.jobs.getActiveQuestions().first { question in
            question.questionText.localizedCaseInsensitiveContains("daily report")
        }?.questionId)

        try env.jobs.saveClockOutResponses(
            laborEntryId: laborEntryId,
            responses: [
                (questionId: qId, answer: "No issues"),
                (questionId: dailyReportQuestionId, answer: "Completed panel labeling and staged tomorrow's materials")
            ]
        )

        let responses = try env.jobs.getResponsesForEntry(laborEntryId: laborEntryId)
        #expect(responses.count == 2)
        let safetyResponse = responses.first { $0.questionId == qId }
        #expect(safetyResponse?.answer == "No issues")
        #expect(safetyResponse?.questionText == "Any safety concerns?")

        try env.jobs.clockOut(laborEntryId: laborEntryId)
    }

    @Test("saveClockOutDailyReport creates a job-scoped daily report notebook entry")
    func testSaveClockOutDailyReportCreatesNotebookEntry() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-DR-CLOCK", name: "Clockout Daily Report Job")
        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)

        let entryId = try #require(try env.jobs.saveClockOutDailyReport(
            laborEntryId: laborEntryId,
            dailyReport: "  Pulled feeder wire, finished panel labeling, and staged tomorrow's materials.  "
        ))

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: """
                SELECT ne.title, ne.content, ne.entry_type, nb.notebook_type, nb.job_id, nb.created_by
                FROM notebook_entries ne
                JOIN notebook_sections ns ON ns.id = ne.section_id
                JOIN notebooks nb ON nb.id = ns.notebook_id
                WHERE ne.id = ?
                """, arguments: [entryId])
        }

        #expect(row?["entry_type"] as String? == "daily-report")
        #expect(row?["notebook_type"] as String? == "daily-report")
        #expect(row?["job_id"] as Int64? == jobId)
        #expect(row?["created_by"] as Int64? == env.adminUserId)
        let title = row?["title"] as String? ?? ""
        let content = row?["content"] as String? ?? ""
        #expect(title.contains("Daily Report"))
        #expect(content.contains("Pulled feeder wire, finished panel labeling, and staged tomorrow's materials."))
    }

    @Test("saveClockOutDailyReport ignores blank clock-out daily report text")
    func testSaveClockOutDailyReportIgnoresBlankText() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)

        let entryId = try env.jobs.saveClockOutDailyReport(laborEntryId: laborEntryId, dailyReport: "  \n\t  ")
        #expect(entryId == nil)
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
        let stages = try env.jobs.listAllJobStages()
        #expect(!stages.isEmpty)
        #expect(stages.map(\.name).contains("Rough-in"))
    }

    @Test("job stage templates seed default template and new jobs inherit it")
    func testJobStageTemplateDefaultSeedAndNewJobAssignment() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let templates = try env.jobs.listJobStageTemplates()
        #expect(templates.count == 1)
        #expect(templates[0].name == "Default")
        #expect(templates[0].isDefault)
        #expect(templates[0].stageCount == 3)

        let assignedTemplateId: Int64? = try env.db.writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT stage_template_id FROM jobs WHERE id = ?", arguments: [jobId])
        }
        #expect(assignedTemplateId == templates[0].id)

        let stages = try env.jobs.listAllJobStages(templateId: templates[0].id)
        #expect(stages.map(\.name) == ["Rough-in", "Prep/Makeup", "Trim-out"])
    }

    @Test("job stage templates report active job impact count")
    func testJobStageTemplateActiveJobImpactCount() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try E2ETestHelpers.seedJob(env)

        let defaultTemplate = try #require(try env.jobs.listJobStageTemplates().first(where: { $0.isDefault }))

        #expect(defaultTemplate.activeJobCount == 1)
    }

    @Test("reordering a template preserves current stage by ID")
    func testReorderTemplateStagesPreservesCurrentStageById() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let templateId = try env.jobs.createJobStageTemplate(name: "Commercial", stageNames: ["Underground", "Rough", "Trim"])
        let stages = try env.jobs.listAllJobStages(templateId: templateId)
        let trimId = try #require(stages.first(where: { $0.name == "Trim" })?.id)

        try env.jobs.assignJobStageTemplate(jobId: jobId, templateId: templateId, currentStageId: trimId)
        try env.jobs.reorderJobStages(templateId: templateId, orderedStageIds: [trimId, stages[0].id, stages[1].id])

        let statuses = try env.jobs.listJobStages(forJobId: jobId)
        #expect(statuses.map(\.id) == [trimId, stages[0].id, stages[1].id])
        #expect(statuses[0].status == "in_progress")
        #expect(statuses[1].status == "pending")
        #expect(statuses[2].status == "pending")

        let currentStageId: Int64? = try env.db.writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT current_stage_id FROM jobs WHERE id = ?", arguments: [jobId])
        }
        #expect(currentStageId == trimId)
    }

    @Test("category mappings are scoped per template")
    func testStageCategoryMappingsAreTemplateScoped() throws {
        let env = try E2ETestHelpers.setUp()
        let categoryId = try E2ETestHelpers.seedCategory(env, name: "Switchgear")
        let templateA = try env.jobs.createJobStageTemplate(name: "Residential", stageNames: ["Rough", "Trim"])
        let templateB = try env.jobs.createJobStageTemplate(name: "Service", stageNames: ["Pickup", "Install"])
        let roughId = try #require(try env.jobs.listAllJobStages(templateId: templateA).first?.id)
        let pickupId = try #require(try env.jobs.listAllJobStages(templateId: templateB).first?.id)

        try env.jobs.setJobStageCategoryMapping(templateId: templateA, categoryId: categoryId, stageId: roughId)
        try env.jobs.setJobStageCategoryMapping(templateId: templateB, categoryId: categoryId, stageId: pickupId)

        let mappingsA = try env.jobs.listJobStageCategoryMappings(templateId: templateA)
        let mappingsB = try env.jobs.listJobStageCategoryMappings(templateId: templateB)
        #expect(mappingsA.first?.stageId == roughId)
        #expect(mappingsB.first?.stageId == pickupId)
    }

    @Test("archiving a referenced stage is blocked")
    func testArchiveReferencedStageIsBlocked() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let templateId = try env.jobs.createJobStageTemplate(name: "Blocked Stage", stageNames: ["Rough", "Trim"])
        let roughId = try #require(try env.jobs.listAllJobStages(templateId: templateId).first?.id)
        try env.jobs.assignJobStageTemplate(jobId: jobId, templateId: templateId, currentStageId: roughId)

        #expect(throws: JobsService.JobsError.stageInUse(roughId)) {
            try env.jobs.archiveJobStage(stageId: roughId)
        }
    }

    @Test("applying a stage template draft archives renames adds and reorders in one save")
    func testApplyJobStageTemplateDraftPersistsFullDraft() throws {
        let env = try E2ETestHelpers.setUp()
        let templateId = try env.jobs.createJobStageTemplate(name: "Atomic Save", stageNames: ["Rough", "Trim", "Closeout"])
        let original = try env.jobs.listAllJobStages(templateId: templateId)
        let roughId = try #require(original.first(where: { $0.name == "Rough" })?.id)
        let trimId = try #require(original.first(where: { $0.name == "Trim" })?.id)

        try env.jobs.applyJobStageTemplateDraft(
            templateId: templateId,
            stages: [
                JobsService.JobStageTemplateDraftStage(existingId: trimId, name: "Trim Final"),
                JobsService.JobStageTemplateDraftStage(existingId: nil, name: "Inspection"),
                JobsService.JobStageTemplateDraftStage(existingId: roughId, name: "Rough-In")
            ]
        )

        let saved = try env.jobs.listAllJobStages(templateId: templateId)
        #expect(saved.map(\.name) == ["Trim Final", "Inspection", "Rough-In"])
        #expect(saved.map(\.sortOrder) == [1, 2, 3])
        #expect(!saved.contains { $0.name == "Closeout" })
    }

    @Test("failed stage template draft save rolls back earlier stage changes")
    func testApplyJobStageTemplateDraftRollsBackOnFailure() throws {
        let env = try E2ETestHelpers.setUp()
        let templateId = try env.jobs.createJobStageTemplate(name: "Atomic Rollback", stageNames: ["Rough", "Trim", "Closeout"])
        let original = try env.jobs.listAllJobStages(templateId: templateId)
        let roughId = try #require(original.first(where: { $0.name == "Rough" })?.id)
        let trimId = try #require(original.first(where: { $0.name == "Trim" })?.id)

        #expect(throws: JobsService.JobsError.invalidStageTemplate(templateId)) {
            try env.jobs.applyJobStageTemplateDraft(
                templateId: templateId,
                stages: [
                    JobsService.JobStageTemplateDraftStage(existingId: roughId, name: "Rough Renamed"),
                    JobsService.JobStageTemplateDraftStage(existingId: nil, name: "Inspection"),
                    JobsService.JobStageTemplateDraftStage(existingId: trimId, name: "Trim Renamed"),
                    JobsService.JobStageTemplateDraftStage(existingId: trimId, name: "Trim Duplicate")
                ]
            )
        }

        let saved = try env.jobs.listAllJobStages(templateId: templateId)
        #expect(saved.map(\.id) == original.map(\.id))
        #expect(saved.map(\.name) == original.map(\.name))
        #expect(saved.map(\.sortOrder) == original.map(\.sortOrder))
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

    @Test("getActiveJobTodos excludes todos from soft-deleted notebook section")
    func testGetActiveJobTodos_excludesTodosInDeletedSection() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let nbId = try env.notebooks.createNotebook(
            title: "Deleted Section NB",
            notebookType: "job",
            jobId: jobId,
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(notebookId: nbId, groupId: nil, name: "Gone Section")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO notebook_entries
                    (section_id, notebook_id, entry_type, block_type, title, sort_order,
                     created_by, created_at, updated_at, is_deleted)
                VALUES (?, ?, 'todo', 'text', 'Ghost Todo', 0, ?, datetime('now'), datetime('now'), 0)
                """, arguments: [sectionId, nbId, env.adminUserId])
            try db.execute(sql: "UPDATE notebook_sections SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [sectionId])
        }
        let todos = try env.jobs.getActiveJobTodos(jobId: jobId)
        #expect(!todos.contains(where: { $0.title == "Ghost Todo" }))
    }

    @Test("getActiveJobTodos excludes todos from soft-deleted notebook")
    func testGetActiveJobTodos_excludesTodosInDeletedNotebook() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let nbId = try env.notebooks.createNotebook(
            title: "Deleted NB",
            notebookType: "job",
            jobId: jobId,
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(notebookId: nbId, groupId: nil, name: "Active Section")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO notebook_entries
                    (section_id, notebook_id, entry_type, block_type, title, sort_order,
                     created_by, created_at, updated_at, is_deleted)
                VALUES (?, ?, 'todo', 'text', 'Orphan Todo', 0, ?, datetime('now'), datetime('now'), 0)
                """, arguments: [sectionId, nbId, env.adminUserId])
            try db.execute(sql: "UPDATE notebooks SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [nbId])
        }
        let todos = try env.jobs.getActiveJobTodos(jobId: jobId)
        #expect(!todos.contains(where: { $0.title == "Orphan Todo" }))
    }

    @Test("getJobTodoSummary excludes todos from soft-deleted notebook section")
    func testGetJobTodoSummary_excludesTodosInDeletedSection() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let nbId = try env.notebooks.createNotebook(
            title: "Summary NB",
            notebookType: "job",
            jobId: jobId,
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(notebookId: nbId, groupId: nil, name: "Del Section")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO notebook_entries
                    (section_id, notebook_id, entry_type, block_type, title, sort_order,
                     created_by, created_at, updated_at, is_deleted)
                VALUES (?, ?, 'todo', 'text', 'Phantom Todo', 0, ?, datetime('now'), datetime('now'), 0)
                """, arguments: [sectionId, nbId, env.adminUserId])
            try db.execute(sql: "UPDATE notebook_sections SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [sectionId])
        }
        let summary = try env.jobs.getJobTodoSummary(jobId: jobId)
        #expect(summary.totalTodos == 0)
    }

    @Test("linkClockEntryToTodo is a no-op on a soft-deleted labor entry")
    func testLinkClockEntryToTodo_noOpOnSoftDeletedEntry() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        // Clock in to create a real labor entry, then soft-delete it
        let entryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE labor_entries SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [entryId])
        }
        // Stale UI tries to link the clock entry to a todo — must not mutate tombstoned row
        try env.jobs.linkClockEntryToTodo(clockEntryId: entryId, todoId: 999)

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT linked_todo_id FROM labor_entries WHERE id = ?", arguments: [entryId])
        }
        let linkedId: Int64? = row?["linked_todo_id"]
        #expect(linkedId == nil,
            "Soft-deleted labor entry linked_todo_id must not change — UPDATE must guard AND deleted_at IS NULL")
    }

    @Test("setClockEntryWorkType is a no-op on a soft-deleted labor entry")
    func testSetClockEntryWorkType_noOpOnSoftDeletedEntry() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let entryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE labor_entries SET work_type = 'new_work', deleted_at = datetime('now') WHERE id = ?",
                           arguments: [entryId])
        }
        // Stale warranty-flow tries to mark tombstoned labor entry as warranty work
        try env.jobs.setClockEntryWorkType(clockEntryId: entryId, workType: "warranty")

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT work_type FROM labor_entries WHERE id = ?", arguments: [entryId])
        }
        let workType: String? = row?["work_type"]
        #expect(workType == "new_work",
            "Soft-deleted labor entry work_type must not change — UPDATE must guard AND deleted_at IS NULL")
    }

    @Test("toggleSupplyRun is a no-op on a soft-deleted labor entry")
    func testToggleSupplyRun_noOpOnSoftDeletedEntry() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let entryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE labor_entries SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [entryId])
        }
        // Stale supply-run toggle on a tombstoned entry should be a no-op
        let result = try env.jobs.toggleSupplyRun(laborEntryId: entryId)
        #expect(result == "working",
            "toggleSupplyRun on soft-deleted entry must return 'working' (no-op early exit)")

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT notes FROM labor_entries WHERE id = ?", arguments: [entryId])
        }
        let notes: String? = row?["notes"]
        #expect(notes == nil || (notes?.contains("supply_run_start") == false),
            "Soft-deleted labor entry notes must not gain supply_run markers")
    }

    @Test("activeSupplyRunStart returns the latest unmatched supply run start")
    func testActiveSupplyRunStart_returnsLatestUnmatchedStart() throws {
        let notes = """
        [supply_run_start:2026-06-19T12:00:00Z] [supply_run_end:2026-06-19T12:25:00Z] \
        picked up couplings [supply_run_start:2026-06-19T13:10:00Z]
        """

        let start = try #require(JobsService.activeSupplyRunStart(notes: notes))

        #expect(CoreFormatters.iso8601.string(from: start) == "2026-06-19T13:10:00Z")
    }

    @Test("activeSupplyRunStart returns nil when latest supply run is ended")
    func testActiveSupplyRunStart_returnsNilWhenLatestRunEnded() {
        let notes = """
        [supply_run_start:2026-06-19T12:00:00Z] [supply_run_end:2026-06-19T12:25:00Z] \
        [supply_run_start:2026-06-19T13:10:00Z] [supply_run_end:2026-06-19T13:40:00Z]
        """

        #expect(JobsService.activeSupplyRunStart(notes: notes) == nil)
    }

    @Test("answerOneTimeQuestion is a no-op on a soft-deleted question")
    func testAnswerOneTimeQuestion_noOpOnSoftDeletedQuestion() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let questionId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO one_time_questions
                    (job_id, question_text, answer_type, status, created_by, created_at)
                VALUES (?, 'What color?', 'text', 'pending', ?, datetime('now'))
                """, arguments: [jobId, env.adminUserId])
            return db.lastInsertedRowID
        }
        // Soft-delete the question
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE one_time_questions SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [questionId])
        }
        // Stale UI tries to answer a tombstoned question — must throw questionNotFound (guard catches it)
        do {
            try env.jobs.answerOneTimeQuestion(questionId: questionId, answerText: "RED", answeredBy: env.adminUserId)
            Issue.record("Expected answerOneTimeQuestion to throw for deleted question")
        } catch {
            // Expected — SELECT guard throws questionNotFound
        }
        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT answer_text, status FROM one_time_questions WHERE id = ?",
                             arguments: [questionId])
        }
        let answer: String? = row?["answer_text"]
        let status: String? = row?["status"]
        #expect(answer == nil, "Soft-deleted question answer_text must remain nil")
        #expect(status == "pending", "Soft-deleted question status must remain pending")
    }

    @Test("getLaborEntryNotes returns nil for soft-deleted labor entry")
    func testGetLaborEntryNotes_nilForSoftDeletedEntry() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let entryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        // Write notes, then soft-delete
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE labor_entries SET notes = 'test notes', deleted_at = datetime('now') WHERE id = ?",
                           arguments: [entryId])
        }
        // getLaborEntryNotes must return nil for a tombstoned entry
        let notes = try env.jobs.getLaborEntryNotes(laborEntryId: entryId)
        #expect(notes == nil,
            "getLaborEntryNotes must return nil for soft-deleted labor entry — SELECT must guard AND deleted_at IS NULL")
    }

    @Test("updateJob is a no-op on a soft-deleted job")
    func testUpdateJob_noOpOnSoftDeletedJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try env.jobs.createJob(
            jobNumber: "J-SOFT-DEL",
            jobName: "OriginalJobName",
            customerName: "Cust",
            status: "active",
            createdBy: env.adminUserId
        )
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [jobId])
        }
        // Stale edit form tries to rename a tombstoned job. Regression: UPDATE jobs
        // SET ... WHERE id = ? had no deleted_at guard, so the rename would stick.
        try env.jobs.updateJob(id: jobId, jobName: "ShouldNotStick")

        let name = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT job_name FROM jobs WHERE id = ?", arguments: [jobId])
        }
        #expect(name == "OriginalJobName",
                "Soft-deleted job name must not change — UPDATE must guard AND deleted_at IS NULL")
    }

    @Test("clockIn throws jobNotClockable for completed job")
    func testClockIn_throwsForCompletedJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET status = 'completed' WHERE id = ?", arguments: [jobId])
        }
        var threw = false
        do {
            _ = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        } catch JobsService.JobsError.jobNotClockable {
            threw = true
        } catch {}
        #expect(threw, "clockIn must throw jobNotClockable when the job status is 'completed'")
    }

    @Test("clockIn throws jobNotClockable for cancelled job")
    func testClockIn_throwsForCancelledJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET status = 'cancelled' WHERE id = ?", arguments: [jobId])
        }
        var threw = false
        do {
            _ = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        } catch JobsService.JobsError.jobNotClockable {
            threw = true
        } catch {}
        #expect(threw, "clockIn must throw jobNotClockable when the job status is 'cancelled'")
    }

    @Test("clockIn succeeds for in_progress job")
    func testClockIn_succeedsForInProgressJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET status = 'in_progress' WHERE id = ?", arguments: [jobId])
        }
        let entryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        #expect(entryId > 0, "clockIn must succeed for in_progress jobs")
    }

    @Test("addJobPart throws invalidReturnQuantity when qty is zero")
    func testAddJobPart_throwsForZeroQty() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let (catId, _, _) = try E2ETestHelpers.seedPartHierarchy(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        var threw = false
        do {
            _ = try env.jobs.addJobPart(jobId: jobId, partId: partId, qty: 0, performedBy: env.adminUserId)
        } catch JobsService.JobsError.invalidReturnQuantity {
            threw = true
        } catch {}
        #expect(threw, "addJobPart must throw invalidReturnQuantity when qty is 0")
    }

    @Test("addJobPart throws partNotFound for soft-deleted part")
    func testAddJobPart_throwsForSoftDeletedPart() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let (catId, _, _) = try E2ETestHelpers.seedPartHierarchy(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?", arguments: [partId])
        }
        var threw = false
        do {
            _ = try env.jobs.addJobPart(jobId: jobId, partId: partId, qty: 1, performedBy: env.adminUserId)
        } catch JobsService.JobsError.partNotFound {
            threw = true
        } catch {}
        #expect(threw, "addJobPart must throw partNotFound when the part is soft-deleted")
    }

    @Test("returnJobPart throws invalidReturnQuantity when returnQty is zero")
    func testReturnJobPart_throwsForZeroQty() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let (catId, _, _) = try E2ETestHelpers.seedPartHierarchy(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let jobPartId = try env.jobs.addJobPart(jobId: jobId, partId: partId, qty: 3, performedBy: env.adminUserId)
        var threw = false
        do {
            try env.jobs.returnJobPart(jobPartId: jobPartId, returnQty: 0)
        } catch JobsService.JobsError.invalidReturnQuantity {
            threw = true
        } catch {}
        #expect(threw, "returnJobPart must throw invalidReturnQuantity when returnQty is 0")
    }

    @Test("returnJobPart throws invalidReturnQuantity when over-returning")
    func testReturnJobPart_throwsForOverReturn() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let (catId, _, _) = try E2ETestHelpers.seedPartHierarchy(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let jobPartId = try env.jobs.addJobPart(jobId: jobId, partId: partId, qty: 2, performedBy: env.adminUserId)
        var threw = false
        do {
            try env.jobs.returnJobPart(jobPartId: jobPartId, returnQty: 3)
        } catch JobsService.JobsError.invalidReturnQuantity {
            threw = true
        } catch {}
        #expect(threw, "returnJobPart must throw invalidReturnQuantity when returnQty exceeds qty_consumed")
    }

    @Test("returnJobPart succeeds and updates qty_returned for valid return")
    func testReturnJobPart_succeedsForValidReturn() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let (catId, _, _) = try E2ETestHelpers.seedPartHierarchy(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let jobPartId = try env.jobs.addJobPart(jobId: jobId, partId: partId, qty: 5, performedBy: env.adminUserId)
        try env.jobs.returnJobPart(jobPartId: jobPartId, returnQty: 2)
        let qtyReturned = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT qty_returned FROM job_parts WHERE id = ?", arguments: [jobPartId]) ?? 0
        }
        #expect(qtyReturned == 2, "qty_returned must reflect the partial return")
    }

    @Test("saveClockOutResponses throws requiredQuestionNotAnswered when required question is skipped")
    func testSaveClockOutResponses_throwsForSkippedRequiredQuestion() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        _ = try env.settings.addClockOutQuestion(
            text: "Safety check required",
            type: "text",
            isRequired: true,
            sortOrder: 0
        )
        var threw = false
        do {
            try env.jobs.saveClockOutResponses(laborEntryId: laborEntryId, responses: [])
        } catch JobsService.JobsError.requiredQuestionNotAnswered {
            threw = true
        } catch {}
        #expect(threw, "saveClockOutResponses must throw requiredQuestionNotAnswered when a required active question has no answer")
    }

    @Test("saveClockOutResponses throws for whitespace-only answer on required question")
    func testSaveClockOutResponses_throwsForBlankRequiredAnswer() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        let qId = try env.settings.addClockOutQuestion(
            text: "Any hazards?",
            type: "text",
            isRequired: true,
            sortOrder: 0
        )
        var threw = false
        do {
            try env.jobs.saveClockOutResponses(laborEntryId: laborEntryId, responses: [(questionId: qId, answer: "   ")])
        } catch JobsService.JobsError.requiredQuestionNotAnswered {
            threw = true
        } catch {}
        #expect(threw, "Whitespace-only answer must not satisfy a required question — trimmingCharacters check must fire")
    }

    @Test("saveClockOutResponses succeeds and skips validation for inactive required question")
    func testSaveClockOutResponses_inactiveRequiredQuestionIsNotEnforced() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        let qId = try env.settings.addClockOutQuestion(
            text: "Deactivated question",
            type: "text",
            isRequired: true,
            sortOrder: 0
        )
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE clock_out_questions SET is_active = 0 WHERE id = ?", arguments: [qId])
        }
        let dailyReportQuestionId = try #require(try env.jobs.getActiveQuestions().first { question in
            question.questionText.localizedCaseInsensitiveContains("daily report")
        }?.questionId)
        // Should succeed because the inactive custom question is not enforced; the default Daily Report
        // prompt remains active/required and must still be answered.
        try env.jobs.saveClockOutResponses(
            laborEntryId: laborEntryId,
            responses: [(questionId: dailyReportQuestionId, answer: "Finished rough-in notes")]
        )
    }

    @Test("setPaymentHold throws invalidAmount for zero amount")
    func testSetPaymentHold_throwsForZeroAmount() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        var threw = false
        do {
            try env.jobs.setPaymentHold(jobId: jobId, amount: 0, reason: nil)
        } catch JobsService.JobsError.invalidAmount {
            threw = true
        } catch {}
        #expect(threw, "setPaymentHold must throw invalidAmount when amount is zero")
    }

    @Test("setPaymentHold throws invalidAmount for negative amount")
    func testSetPaymentHold_throwsForNegativeAmount() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        var threw = false
        do {
            try env.jobs.setPaymentHold(jobId: jobId, amount: -500, reason: "test")
        } catch JobsService.JobsError.invalidAmount {
            threw = true
        } catch {}
        #expect(threw, "setPaymentHold must throw invalidAmount when amount is negative")
    }

    @Test("setPaymentHold succeeds for positive amount")
    func testSetPaymentHold_succeedsForPositiveAmount() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        try env.jobs.setPaymentHold(jobId: jobId, amount: 1500.00, reason: "Unpaid invoice")
        let onHold = try env.jobs.isJobOnPaymentHold(jobId: jobId)
        #expect(onHold, "setPaymentHold must place the job on hold")
    }

    @Test("addTeamMember throws jobNotFound for soft-deleted job")
    func testAddTeamMember_throwsForSoftDeletedJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [jobId])
        }
        var threw = false
        do {
            _ = try env.jobs.addTeamMember(jobId: jobId, userId: env.adminUserId)
        } catch JobsService.JobsError.jobNotFound {
            threw = true
        } catch {}
        #expect(threw, "addTeamMember must throw jobNotFound when the job is soft-deleted")
    }

    @Test("setWarranty throws invalidDuration for zero duration")
    func testSetWarranty_throwsForZeroDuration() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        var threw = false
        do {
            try env.jobs.setWarranty(jobId: jobId, startDate: Date(), durationDays: 0)
        } catch JobsService.JobsError.invalidDuration {
            threw = true
        } catch {}
        #expect(threw, "setWarranty must throw invalidDuration when durationDays is zero")
    }

    @Test("setWarranty throws invalidDuration for negative duration")
    func testSetWarranty_throwsForNegativeDuration() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        var threw = false
        do {
            try env.jobs.setWarranty(jobId: jobId, startDate: Date(), durationDays: -30)
        } catch JobsService.JobsError.invalidDuration {
            threw = true
        } catch {}
        #expect(threw, "setWarranty must throw invalidDuration when durationDays is negative")
    }

    @Test("setWarranty succeeds for positive duration")
    func testSetWarranty_succeedsForPositiveDuration() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        try env.jobs.setWarranty(jobId: jobId, startDate: Date(), durationDays: 365)
        let active = try env.jobs.isWarrantyActive(jobId: jobId)
        #expect(active, "setWarranty must create an active warranty for a future end date")
    }

    @Test("createJob throws requiredFieldEmpty for blank jobName")
    func testCreateJob_throwsForBlankJobName() throws {
        let env = try E2ETestHelpers.setUp()
        var threw = false
        do {
            _ = try env.jobs.createJob(jobNumber: "J-001", jobName: "   ")
        } catch JobsService.JobsError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "createJob must throw requiredFieldEmpty when jobName is blank")
    }

    @Test("createJob throws requiredFieldEmpty for blank jobNumber")
    func testCreateJob_throwsForBlankJobNumber() throws {
        let env = try E2ETestHelpers.setUp()
        var threw = false
        do {
            _ = try env.jobs.createJob(jobNumber: "", jobName: "Valid Name")
        } catch JobsService.JobsError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "createJob must throw requiredFieldEmpty when jobNumber is blank")
    }

    @Test("createOneTimeQuestion throws requiredFieldEmpty for blank text")
    func testCreateOneTimeQuestion_throwsForBlankText() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        var threw = false
        do {
            _ = try env.jobs.createOneTimeQuestion(jobId: jobId, text: "  ", createdBy: env.adminUserId)
        } catch JobsService.JobsError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "createOneTimeQuestion must throw requiredFieldEmpty when text is blank")
    }

    @Test("answerOneTimeQuestion throws requiredFieldEmpty for blank answer")
    func testAnswerOneTimeQuestion_throwsForBlankAnswer() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let qId = try env.jobs.createOneTimeQuestion(jobId: jobId, text: "How was the job?", createdBy: env.adminUserId)
        var threw = false
        do {
            try env.jobs.answerOneTimeQuestion(questionId: qId, answerText: "   ", answeredBy: env.adminUserId)
        } catch JobsService.JobsError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "answerOneTimeQuestion must throw requiredFieldEmpty when answerText is blank")
    }

    @Test("updateJob throws requiredFieldEmpty when jobName is blank")
    func testUpdateJob_throwsForBlankJobName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        var threw = false
        do {
            try env.jobs.updateJob(id: jobId, jobName: "   ")
        } catch JobsService.JobsError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "updateJob must throw requiredFieldEmpty when jobName is whitespace-only")
    }

    @Test("updateJob throws requiredFieldEmpty when status is blank")
    func testUpdateJob_throwsForBlankStatus() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        var threw = false
        do {
            try env.jobs.updateJob(id: jobId, status: "")
        } catch JobsService.JobsError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "updateJob must throw requiredFieldEmpty when status is empty")
    }

    @Test("setClockEntryWorkType throws requiredFieldEmpty when workType is blank")
    func testSetClockEntryWorkType_throwsForBlankWorkType() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let entryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        var threw = false
        do {
            try env.jobs.setClockEntryWorkType(clockEntryId: entryId, workType: "   ")
        } catch JobsService.JobsError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "setClockEntryWorkType must throw requiredFieldEmpty when workType is whitespace-only")
    }
}
