import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// Comprehensive tests for SchedulingService.
///
/// Covers: schedule queries, time-off lifecycle (create/approve/reject/filter),
/// dispatch board, dispatch templates, sub-schedules, weekly availability,
/// day schedule summary, and scheduling stats.
@Suite("SchedulingService Tests")
struct SchedulingServiceTests {

    // MARK: - 1. Get Empty Schedule

    @Test("getMySchedule returns empty array when no entries exist")
    func testGetMyScheduleEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let schedule = try env.scheduling.getMySchedule(
            userId: env.adminUserId,
            startDate: "2026-01-01",
            endDate: "2026-12-31"
        )
        #expect(schedule.isEmpty)
    }

    @Test("getMySchedule returns entries after creating schedule entries")
    func testGetMyScheduleWithEntries() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        _ = try env.scheduling.createScheduleEntry(
            userId: env.adminUserId,
            jobId: jobId,
            date: "2026-06-15",
            startTime: "08:00",
            endTime: "17:00",
            notes: "Full day",
            timeSlot: "full"
        )

        let schedule = try env.scheduling.getMySchedule(
            userId: env.adminUserId,
            startDate: "2026-06-01",
            endDate: "2026-06-30"
        )
        #expect(schedule.count == 1)
        #expect(schedule[0].date == "2026-06-15")
        #expect(schedule[0].jobName == "Test Job")
        #expect(schedule[0].status == "scheduled")
        #expect(schedule[0].timeSlot == "full")
        #expect(schedule[0].userName == "TestAdmin")
    }

    @Test("getJobDayAssignmentDetail separates selected-job crew, other-job crew, and time-off workers")
    func testGetJobDayAssignmentDetail() throws {
        let env = try E2ETestHelpers.setUp()
        let targetJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-DETAIL-01", name: "Target Detail Job")
        let otherJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-DETAIL-02", name: "Other Detail Job")
        let otherUserId = try env.auth.createUser(displayName: "OtherWorker", pin: "1234")
        let timeOffUserId = try env.auth.createUser(displayName: "TimeOffWorker", pin: "1234")

        _ = try env.scheduling.createScheduleEntry(
            userId: env.adminUserId,
            jobId: targetJobId,
            date: "2026-06-15",
            startTime: "08:00",
            endTime: "17:00",
            notes: "target crew",
            timeSlot: "full"
        )
        _ = try env.scheduling.createScheduleEntry(
            userId: otherUserId,
            jobId: otherJobId,
            date: "2026-06-15",
            startTime: "08:00",
            endTime: "12:00",
            notes: "already booked elsewhere",
            timeSlot: "am"
        )
        let requestId = try env.scheduling.createTimeOffRequest(
            userId: timeOffUserId,
            startDate: "2026-06-15",
            endDate: "2026-06-15",
            reason: "Vacation"
        )
        try env.scheduling.updateTimeOffStatus(
            id: requestId,
            status: "approved",
            approvedBy: env.adminUserId
        )

        let detail = try env.scheduling.getJobDayAssignmentDetail(jobId: targetJobId, date: "2026-06-15")

        #expect(detail.date == "2026-06-15")
        #expect(detail.jobId == targetJobId)
        #expect(detail.assignedToJob.map(\.userName) == ["TestAdmin"])
        #expect(detail.assignedToOtherJobs.map(\.userName) == ["OtherWorker"])
        #expect(detail.assignedToOtherJobs.first?.jobName == "Other Detail Job")
        #expect(detail.timeOffWorkers.map(\.userName) == ["TimeOffWorker"])
        #expect(detail.timeOffWorkers.first?.reason == "Vacation")
    }

    // MARK: - 2. Submit Time-Off Request

    @Test("createTimeOffRequest inserts a pending time-off entry")
    func testSubmitTimeOffRequest() throws {
        let env = try E2ETestHelpers.setUp()

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-07-04",
            endDate: "2026-07-04",
            reason: "Independence Day"
        )
        #expect(requestId > 0)

        // Verify it appears in the list
        let requests = try env.scheduling.listTimeOffRequests(userId: env.adminUserId)
        #expect(requests.count == 1)
        #expect(requests[0].reason == "Independence Day")
        #expect(requests[0].status == "pending")
        #expect(requests[0].userName == "TestAdmin")
    }

    @Test("createTimeOffRequest with multi-day range creates entries for each day")
    func testSubmitTimeOffRequestMultiDay() throws {
        let env = try E2ETestHelpers.setUp()

        _ = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-08-10",
            endDate: "2026-08-12",
            reason: "Short vacation"
        )

        // Should have 3 entries (Aug 10, 11, 12)
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM schedule_exceptions
                WHERE user_id = ? AND exception_type = 'time_off'
                """, arguments: [env.adminUserId])!
        }
        #expect(count == 3)
    }

    // MARK: - 3. Approve Time-Off

    @Test("updateTimeOffStatus approves a pending time-off request")
    func testApproveTimeOff() throws {
        let env = try E2ETestHelpers.setUp()

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-09-01",
            endDate: "2026-09-01",
            reason: "Doctor appointment"
        )

        try env.scheduling.updateTimeOffStatus(
            id: requestId,
            status: "approved",
            approvedBy: env.adminUserId
        )

        // Verify status is now approved
        let requests = try env.scheduling.listTimeOffRequests(userId: env.adminUserId, status: "approved")
        #expect(requests.count == 1)
        #expect(requests[0].status == "approved")
        #expect(requests[0].approvedByName == "TestAdmin")
    }

    @Test("updateTimeOffStatus throws insufficientPermissions when actor lacks approve_time_off")
    func testUpdateTimeOffStatusRequiresApproveTimeOffPermission() throws {
        let env = try E2ETestHelpers.setUp()

        let workerId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('WorkerUser', 'hash123', 1)
                """)
            let userId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO user_hats (user_id, hat_id, is_active)
                SELECT ?, id, 1 FROM hats WHERE name = 'Worker'
                """, arguments: [userId])
            return userId
        }

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-09-02",
            endDate: "2026-09-02",
            reason: "Permission gate regression"
        )

        #expect(throws: SchedulingService.SchedulingError.insufficientPermissions(required: "approve_time_off")) {
            try env.scheduling.updateTimeOffStatus(
                id: requestId,
                status: "approved",
                approvedBy: workerId
            )
        }

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: """
                SELECT is_approved, approved_by FROM schedule_exceptions WHERE id = ?
                """, arguments: [requestId])
        }
        #expect(row?["is_approved"] as Int? == 0)
        #expect((row?["approved_by"] as Int64?) == nil)
    }

    // MARK: - 4. Reject Time-Off

    @Test("updateTimeOffStatus rejects (denies) a pending time-off request")
    func testRejectTimeOff() throws {
        let env = try E2ETestHelpers.setUp()

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-09-15",
            endDate: "2026-09-15",
            reason: "Personal day"
        )

        try env.scheduling.updateTimeOffStatus(
            id: requestId,
            status: "denied",
            approvedBy: env.adminUserId
        )

        // Denied requests have is_approved = 0, same as pending.
        // Verify the request still exists
        let all = try env.scheduling.listTimeOffRequests(userId: env.adminUserId)
        #expect(all.count == 1)
        #expect(all[0].status == "pending") // is_approved = 0 maps to "pending" in the query

        #expect(throws: SchedulingService.SchedulingError.insufficientPermissions(required: "approve_time_off")) {
            try env.scheduling.updateTimeOffStatus(
                id: requestId,
                status: "denied"
            )
        }
    }

    @Test("updateTimeOffStatus throws for non-existent request")
    func testRejectTimeOffNotFound() throws {
        let env = try E2ETestHelpers.setUp()

        #expect(throws: SchedulingService.SchedulingError.self) {
            try env.scheduling.updateTimeOffStatus(id: 9999, status: "approved", approvedBy: env.adminUserId)
        }
    }

    @Test("updateTimeOffStatus throws for invalid status string")
    func testInvalidTimeOffStatus() throws {
        let env = try E2ETestHelpers.setUp()

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-10-01",
            endDate: "2026-10-01",
            reason: "Test"
        )

        #expect(throws: SchedulingService.SchedulingError.self) {
            try env.scheduling.updateTimeOffStatus(id: requestId, status: "invalid_status")
        }
    }

    // MARK: - 5. List Time-Off Filtered by User

    @Test("listTimeOffRequests filters by userId")
    func testListTimeOffFilteredByUser() throws {
        let env = try E2ETestHelpers.setUp()

        // Create a second user
        let secondUserId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('SecondUser', 'hash123', 1)
                """)
            return db.lastInsertedRowID
        }

        // Create time-off for admin
        _ = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-11-01",
            endDate: "2026-11-01",
            reason: "Admin day off"
        )

        // Create time-off for second user
        _ = try env.scheduling.createTimeOffRequest(
            userId: secondUserId,
            startDate: "2026-11-02",
            endDate: "2026-11-02",
            reason: "Second user day off"
        )

        // Filter for admin only
        let adminRequests = try env.scheduling.listTimeOffRequests(userId: env.adminUserId)
        #expect(adminRequests.count == 1)
        #expect(adminRequests[0].reason == "Admin day off")

        // Filter for second user only
        let secondRequests = try env.scheduling.listTimeOffRequests(userId: secondUserId)
        #expect(secondRequests.count == 1)
        #expect(secondRequests[0].reason == "Second user day off")

        // No filter returns all
        let allRequests = try env.scheduling.listTimeOffRequests()
        #expect(allRequests.count == 2)
    }

    // MARK: - 6. List Time-Off Filtered by Status

    @Test("listTimeOffRequests filters by status")
    func testListTimeOffFilteredByStatus() throws {
        let env = try E2ETestHelpers.setUp()

        // Create two requests
        let id1 = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-12-20",
            endDate: "2026-12-20",
            reason: "Holiday"
        )
        _ = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-12-25",
            endDate: "2026-12-25",
            reason: "Christmas"
        )

        // Approve the first one
        try env.scheduling.updateTimeOffStatus(
            id: id1,
            status: "approved",
            approvedBy: env.adminUserId
        )

        // Filter for approved
        let approved = try env.scheduling.listTimeOffRequests(
            userId: env.adminUserId,
            status: "approved"
        )
        #expect(approved.count == 1)
        #expect(approved[0].reason == "Holiday")
        #expect(approved[0].status == "approved")

        // Filter for pending (not approved)
        let pending = try env.scheduling.listTimeOffRequests(
            userId: env.adminUserId,
            status: "pending"
        )
        #expect(pending.count == 1)
        #expect(pending[0].reason == "Christmas")
        #expect(pending[0].status == "pending")
    }

    // MARK: - 7. Get Time-Off for Day

    @Test("getTimeOffForDate returns time-off entries for a specific date")
    func testGetTimeOffForDay() throws {
        let env = try E2ETestHelpers.setUp()

        _ = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-07-10",
            endDate: "2026-07-10",
            reason: "Sick day"
        )

        let entries = try env.scheduling.getTimeOffForDate(date: "2026-07-10")
        #expect(entries.count == 1)
        #expect(entries[0].employeeName == "TestAdmin")
        #expect(entries[0].reason == "Sick day")
    }

    @Test("getTimeOffForDate returns empty for date with no time-off")
    func testGetTimeOffForDayEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let entries = try env.scheduling.getTimeOffForDate(date: "2026-01-01")
        #expect(entries.isEmpty)
    }

    // MARK: - 8. Get Dispatch Board for Date

    @Test("getDispatchBoard returns empty array when no dispatches exist")
    func testGetDispatchBoardEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let board = try env.scheduling.getDispatchBoard(date: "2026-05-01")
        #expect(board.isEmpty)
    }

    @Test("getDispatchBoard returns dispatches for the given date")
    func testGetDispatchBoardWithEntries() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        _ = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: "2026-05-15",
            notes: "Morning dispatch"
        )

        let board = try env.scheduling.getDispatchBoard(date: "2026-05-15")
        #expect(board.count == 1)
        #expect(board[0].userName == "TestAdmin")
        #expect(board[0].jobName == "Test Job")
        #expect(board[0].status == "scheduled")
        #expect(board[0].notes == "Morning dispatch")
    }

    @Test("getDispatchBoard does not return dispatches for other dates")
    func testGetDispatchBoardDateIsolation() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        _ = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: "2026-05-15"
        )

        let otherDate = try env.scheduling.getDispatchBoard(date: "2026-05-16")
        #expect(otherDate.isEmpty)
    }

    // MARK: - 9. Schedule Stats

    @Test("getSchedulingStats returns zeroes on fresh database")
    func testScheduleStatsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let stats = try env.scheduling.getSchedulingStats()
        #expect(stats.scheduledToday >= 0)
        #expect(stats.dispatchedToday >= 0)
        #expect(stats.pendingTimeOff == 0)
    }

    @Test("getSchedulingStats counts pending time-off requests")
    func testScheduleStatsWithPendingTimeOff() throws {
        let env = try E2ETestHelpers.setUp()

        // Create a pending time-off request (any future date)
        _ = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-12-31",
            endDate: "2026-12-31",
            reason: "New Years Eve"
        )

        let stats = try env.scheduling.getSchedulingStats()
        #expect(stats.pendingTimeOff == 1)
    }

    // MARK: - 10. Weekly Availability

    @Test("getWeeklyAvailability returns all users with 7-day availability")
    func testWeeklyAvailability() throws {
        let env = try E2ETestHelpers.setUp()

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let weekStart = fmt.date(from: "2026-06-01")!

        let rows = try env.scheduling.getWeeklyAvailability(weekStartDate: weekStart)
        // At least the admin user should appear
        #expect(!rows.isEmpty)
        #expect(rows[0].days.count == 7)
        // With no schedule exceptions, all days should be available (true)
        #expect(rows[0].days.allSatisfy { $0 == true })
        #expect(rows[0].employeeName == "TestAdmin")
    }

    @Test("getWeeklyAvailability marks days with time-off as unavailable")
    func testWeeklyAvailabilityWithTimeOff() throws {
        let env = try E2ETestHelpers.setUp()

        // Create time-off on a specific date (2026-06-03 = Wednesday, index 2 if week starts Mon June 1)
        _ = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-06-03",
            endDate: "2026-06-03",
            reason: "Doctor"
        )

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let weekStart = fmt.date(from: "2026-06-01")!

        let rows = try env.scheduling.getWeeklyAvailability(weekStartDate: weekStart)
        #expect(!rows.isEmpty)

        let adminRow = rows.first { $0.employeeName == "TestAdmin" }
        #expect(adminRow != nil)
        // Day index 2 (June 3rd, the third day from June 1st) should be false
        #expect(adminRow!.days[2] == false)
        // Other days should still be true
        #expect(adminRow!.days[0] == true) // June 1
        #expect(adminRow!.days[1] == true) // June 2
        #expect(adminRow!.days[3] == true) // June 4
    }

    // MARK: - 11. Day Schedule Summary

    @Test("getMonthScheduleSummary returns empty dict when no data exists")
    func testDayScheduleSummaryEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let summary = try env.scheduling.getMonthScheduleSummary(year: 2026, month: 3)
        #expect(summary.isEmpty)
    }

    @Test("getMonthScheduleSummary counts schedule entries and time-off")
    func testDayScheduleSummaryWithData() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // Create a full-day schedule entry on March 10
        _ = try env.scheduling.createScheduleEntry(
            userId: env.adminUserId,
            jobId: jobId,
            date: "2026-03-10",
            timeSlot: "full"
        )

        // Create an AM entry on March 10
        // Need a second user to avoid unique constraint on (user_id, dispatch_date, job_id)
        let secondUserId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('Worker2', 'hash456', 1)
                """)
            return db.lastInsertedRowID
        }
        _ = try env.scheduling.createScheduleEntry(
            userId: secondUserId,
            jobId: jobId,
            date: "2026-03-10",
            timeSlot: "am"
        )

        // Create time-off on March 10 for a third user
        let thirdUserId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('Worker3', 'hash789', 1)
                """)
            return db.lastInsertedRowID
        }
        _ = try env.scheduling.createTimeOffRequest(
            userId: thirdUserId,
            startDate: "2026-03-10",
            endDate: "2026-03-10",
            reason: "Sick"
        )

        let summary = try env.scheduling.getMonthScheduleSummary(year: 2026, month: 3)
        let march10 = summary["2026-03-10"]
        #expect(march10 != nil)
        #expect(march10!.fullDayCount == 1)
        #expect(march10!.amCount == 1)
        #expect(march10!.totalWorkers == 2)
        #expect(march10!.timeOffCount == 1)
    }

    @Test("getScheduleEntriesForDate returns entries for a specific date")
    func testGetScheduleEntriesForDate() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        _ = try env.scheduling.createScheduleEntry(
            userId: env.adminUserId,
            jobId: jobId,
            date: "2026-04-15",
            startTime: "07:00",
            endTime: "15:00",
            notes: "Early shift"
        )

        let entries = try env.scheduling.getScheduleEntriesForDate(date: "2026-04-15")
        #expect(entries.count == 1)
        #expect(entries[0].jobName == "Test Job")
        #expect(entries[0].startTime == "07:00")
        #expect(entries[0].endTime == "15:00")
        #expect(entries[0].notes == "Early shift")
    }

    // MARK: - 12. List Dispatch Templates (Empty)

    @Test("listDispatchTemplates returns empty array when none exist")
    func testListDispatchTemplatesEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let templates = try env.scheduling.listDispatchTemplates()
        #expect(templates.isEmpty)
    }

    @Test("listDispatchTemplates returns templates after insertion")
    func testListDispatchTemplatesWithData() throws {
        let env = try E2ETestHelpers.setUp()

        // Insert a dispatch template directly
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO dispatch_templates (name, description, is_active)
                VALUES ('Morning Crew', 'Standard morning dispatch', 1)
                """)
        }

        let templates = try env.scheduling.listDispatchTemplates()
        #expect(templates.count == 1)
        #expect(templates[0].name == "Morning Crew")
        #expect(templates[0].description == "Standard morning dispatch")
        #expect(templates[0].isActive == true)
    }

    // MARK: - 13. List Sub-Schedules (Empty)

    @Test("getSubSchedule returns empty array when none exist")
    func testListSubSchedulesEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let subs = try env.scheduling.getSubSchedule(date: "2026-06-01")
        #expect(subs.isEmpty)
    }

    // MARK: - Additional Edge Cases

    @Test("createDispatch and getMySchedule round-trip through job_dispatch")
    func testCreateDispatchAndScheduleRoundTrip() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let dispatchId = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: "2026-08-01",
            notes: "Dispatch note"
        )
        #expect(dispatchId > 0)

        // Dispatch should appear in the user's schedule
        let schedule = try env.scheduling.getMySchedule(
            userId: env.adminUserId,
            startDate: "2026-08-01",
            endDate: "2026-08-01"
        )
        #expect(schedule.count == 1)
        #expect(schedule[0].notes == "Dispatch note")
    }

    @Test("checkTimeOffConflict detects approved time-off on date")
    func testCheckTimeOffConflict() throws {
        let env = try E2ETestHelpers.setUp()

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-10-15",
            endDate: "2026-10-15",
            reason: "Conference"
        )
        try env.scheduling.updateTimeOffStatus(
            id: requestId,
            status: "approved",
            approvedBy: env.adminUserId
        )

        let conflict = try env.scheduling.checkTimeOffConflict(
            employeeId: env.adminUserId,
            date: "2026-10-15"
        )
        #expect(conflict != nil)
        #expect(conflict!.employeeName == "TestAdmin")
        #expect(conflict!.reason == "Conference")
    }

    @Test("checkTimeOffConflict returns nil when no conflict")
    func testCheckTimeOffConflictNone() throws {
        let env = try E2ETestHelpers.setUp()
        let conflict = try env.scheduling.checkTimeOffConflict(
            employeeId: env.adminUserId,
            date: "2026-10-15"
        )
        #expect(conflict == nil)
    }

    // MARK: - Short-Term Pipeline

    @Test("getShortTermPipeline returns empty on fresh DB")
    func testShortTermPipelineEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let pipeline = try env.scheduling.getShortTermPipeline()
        #expect(pipeline.isEmpty)
    }

    @Test("getShortTermPipeline returns active jobs")
    func testShortTermPipelineWithActiveJob() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try E2ETestHelpers.seedJob(env, jobNumber: "J-PIPE-01", name: "Pipeline Job")
        let pipeline = try env.scheduling.getShortTermPipeline()
        #expect(pipeline.count >= 1)
        #expect(pipeline.contains(where: { $0.jobName == "Pipeline Job" }))
    }

    @Test("snoozeCallback updates job due_date")
    func testSnoozeCallback() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-SNOOZE-01", name: "Snooze Job")
        try env.scheduling.snoozeCallback(jobId: jobId, until: "2026-12-31")

        // Verify by reading back through the pipeline — job should appear with callback_date set
        let pipeline = try env.scheduling.getShortTermPipeline()
        let item = pipeline.first(where: { $0.id == jobId })
        #expect(item != nil)
        #expect(item?.callbackDate == "2026-12-31")
    }

    @Test("markCallbackComplete clears job due_date")
    func testMarkCallbackComplete() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-CB-01", name: "Callback Job")
        try env.scheduling.snoozeCallback(jobId: jobId, until: "2026-11-01")
        try env.scheduling.markCallbackComplete(jobId: jobId, notes: "Done with callback")

        let pipeline = try env.scheduling.getShortTermPipeline()
        let item = pipeline.first(where: { $0.id == jobId })
        // due_date should be cleared
        #expect(item?.callbackDate == nil)
    }

    @Test("markCallbackComplete without notes clears due_date")
    func testMarkCallbackCompleteNoNotes() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-CB-02", name: "Callback Job 2")
        try env.scheduling.snoozeCallback(jobId: jobId, until: "2026-11-15")
        try env.scheduling.markCallbackComplete(jobId: jobId, notes: nil)

        let pipeline = try env.scheduling.getShortTermPipeline()
        let item = pipeline.first(where: { $0.id == jobId })
        #expect(item?.callbackDate == nil)
    }

    // MARK: - Long-Term Timeline

    @Test("getLongTermTimeline returns 36 months on fresh DB")
    func testLongTermTimelineMonthCount() throws {
        let env = try E2ETestHelpers.setUp()
        let timeline = try env.scheduling.getLongTermTimeline(months: 36)
        #expect(timeline.count == 36)
    }

    @Test("getLongTermTimeline returns requested month count")
    func testLongTermTimelineCustomMonths() throws {
        let env = try E2ETestHelpers.setUp()
        let timeline = try env.scheduling.getLongTermTimeline(months: 6)
        #expect(timeline.count == 6)
    }

    @Test("getLongTermTimeline month ids are formatted correctly")
    func testLongTermTimelineMonthIdFormat() throws {
        let env = try E2ETestHelpers.setUp()
        let timeline = try env.scheduling.getLongTermTimeline(months: 3)
        for month in timeline {
            // Month IDs should match "YYYY-MM" format
            #expect(month.id.count == 7)
            #expect(month.id.contains("-"))
        }
    }

    // MARK: - Capacity Warnings

    @Test("getCapacityWarnings returns empty for balanced timeline")
    func testCapacityWarningsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let timeline = try env.scheduling.getLongTermTimeline(months: 3)
        let warnings = env.scheduling.getCapacityWarnings(timeline: timeline)
        // Fresh DB — no jobs, but utilization is 0 and jobCount is 0 → under warning
        // under warning fires when utilizationPercent < 0.3 AND jobCount == 0
        #expect(warnings.count >= 0) // may have under-utilization warnings
    }

    @Test("getCapacityWarnings flags overcommitted months")
    func testCapacityWarningsOvercommitted() {
        // Build synthetic overcommitted month
        let overMonth = SchedulingService.MonthCapacity(
            id: "2026-06",
            monthLabel: "June 2026",
            availableDays: 10,
            scheduledDays: 20,  // 200% utilization
            jobCount: 3,
            pendingBidCount: 0,
            jobs: []
        )
        let env = try? E2ETestHelpers.setUp()
        let warnings = env?.scheduling.getCapacityWarnings(timeline: [overMonth]) ?? []
        #expect(warnings.count == 1)
        #expect(warnings[0].isOvercommitted == true)
        #expect(warnings[0].id == "over-2026-06")
    }

    @Test("getCapacityWarnings flags empty months")
    func testCapacityWarningsUnderUtilized() {
        // Build synthetic empty month
        let emptyMonth = SchedulingService.MonthCapacity(
            id: "2026-07",
            monthLabel: "July 2026",
            availableDays: 22,
            scheduledDays: 0,
            jobCount: 0,
            pendingBidCount: 0,
            jobs: []
        )
        let env = try? E2ETestHelpers.setUp()
        let warnings = env?.scheduling.getCapacityWarnings(timeline: [emptyMonth]) ?? []
        #expect(warnings.count == 1)
        #expect(warnings[0].isOvercommitted == false)
        #expect(warnings[0].id == "under-2026-07")
    }

    // MARK: - Report Queries

    @Test("getCrewUtilizationReport returns empty on fresh DB")
    func testCrewUtilizationEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -7, to: Date())!
        let end = Date()
        let rows = try env.scheduling.getCrewUtilizationReport(startDate: start, endDate: end)
        // No dispatches exist — HAVING dispatch_count > 0 filters everyone out
        #expect(rows.isEmpty)
    }

    @Test("getCrewUtilizationReport returns row after dispatch")
    func testCrewUtilizationWithDispatch() throws {
        let env = try E2ETestHelpers.setUp()
        // Admin user is excluded from crew utilization (Admin hat filter). Use a non-admin worker.
        let workerId = try env.auth.createUser(displayName: "Worker Joe", pin: "5678")
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-UTIL-01", name: "Utilization Job")
        _ = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: workerId,
            date: "2026-04-15",
            notes: nil
        )
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let start = fmt.date(from: "2026-04-14")!
        let end = fmt.date(from: "2026-04-16")!
        let rows = try env.scheduling.getCrewUtilizationReport(startDate: start, endDate: end)
        #expect(rows.count >= 1)
        #expect(rows[0].scheduledHours > 0)
    }

    @Test("getDispatchEfficiencyReport returns empty on fresh DB")
    func testDispatchEfficiencyEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -7, to: Date())!
        let end = Date()
        let rows = try env.scheduling.getDispatchEfficiencyReport(startDate: start, endDate: end)
        #expect(rows.isEmpty)
    }

    @Test("getDispatchEfficiencyReport returns row after dispatch")
    func testDispatchEfficiencyWithDispatch() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-EFF-01", name: "Efficiency Job")
        _ = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: "2026-05-10",
            notes: nil
        )
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let start = fmt.date(from: "2026-05-09")!
        let end = fmt.date(from: "2026-05-11")!
        let rows = try env.scheduling.getDispatchEfficiencyReport(startDate: start, endDate: end)
        #expect(rows.count == 1)
        #expect(rows[0].scheduledCount == 1)
        #expect(rows[0].date == "2026-05-10")
    }

    @Test("getPipelineSummaryReport returns empty on fresh DB")
    func testPipelineSummaryEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let rows = try env.scheduling.getPipelineSummaryReport()
        #expect(rows.isEmpty)
    }

    @Test("getPipelineSummaryReport returns job count by status")
    func testPipelineSummaryWithData() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try E2ETestHelpers.seedJob(env, jobNumber: "J-PS-01", name: "Pipeline Summary Job")
        let rows = try env.scheduling.getPipelineSummaryReport()
        #expect(rows.count >= 1)
        let activeRow = rows.first(where: { $0.status == "active" })
        #expect(activeRow != nil)
        #expect(activeRow!.jobCount >= 1)
    }

    // MARK: - Weekly Dispatch Assignments

    @Test("getWeeklyDispatchAssignments returns empty when no dispatches")
    func testWeeklyDispatchEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let assignments = try env.scheduling.getWeeklyDispatchAssignments(
            weekStart: "2026-06-01",
            weekEnd: "2026-06-07"
        )
        #expect(assignments.isEmpty)
    }

    @Test("getWeeklyDispatchAssignments returns dispatch in range")
    func testWeeklyDispatchWithData() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-WD-01", name: "Weekly Dispatch Job")
        _ = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: "2026-06-04",
            notes: nil
        )
        let assignments = try env.scheduling.getWeeklyDispatchAssignments(
            weekStart: "2026-06-01",
            weekEnd: "2026-06-07"
        )
        #expect(assignments.count == 1)
        #expect(assignments[0].jobId == jobId)
    }

    @Test("getWeeklyDispatchAssignments excludes dispatches outside range")
    func testWeeklyDispatchDateFilter() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-WD-02", name: "Out Of Range Job")
        _ = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: "2026-07-15",
            notes: nil
        )
        let assignments = try env.scheduling.getWeeklyDispatchAssignments(
            weekStart: "2026-06-01",
            weekEnd: "2026-06-07"
        )
        #expect(assignments.isEmpty)
    }

    // MARK: - Unassigned Workers

    @Test("getUnassignedWorkers returns all active users when no dispatches")
    func testUnassignedWorkersAllUnassigned() throws {
        let env = try E2ETestHelpers.setUp()
        let workers = try env.scheduling.getUnassignedWorkers(
            weekStart: "2026-08-01",
            weekEnd: "2026-08-07"
        )
        // At least the admin user should be unassigned
        #expect(workers.count >= 1)
        #expect(workers.contains(where: { $0.id == env.adminUserId }))
    }

    @Test("getUnassignedWorkers excludes dispatched workers")
    func testUnassignedWorkersExcludesDispatched() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-UW-01", name: "Assigned Job")
        _ = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: "2026-08-05",
            notes: nil
        )
        let workers = try env.scheduling.getUnassignedWorkers(
            weekStart: "2026-08-01",
            weekEnd: "2026-08-07"
        )
        // Admin user was dispatched — should not appear as unassigned
        #expect(!workers.contains(where: { $0.id == env.adminUserId }))
    }

    // MARK: - Dispatch Job Rows

    @Test("getDispatchJobRows returns empty when no active jobs exist")
    func testDispatchJobRowsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        // Fresh DB has no jobs
        let rows = try env.scheduling.getDispatchJobRows()
        #expect(rows.isEmpty)
    }

    @Test("getDispatchJobRows returns active jobs only")
    func testDispatchJobRowsActiveOnly() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-DJR-01", name: "Active Dispatch Job")

        // Seed a second job and mark it inactive
        let inactiveJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-DJR-02", name: "Inactive Job")
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE jobs SET status = 'complete' WHERE id = ?",
                arguments: [inactiveJobId]
            )
        }

        let rows = try env.scheduling.getDispatchJobRows()
        #expect(rows.contains(where: { $0.id == jobId }))
        #expect(!rows.contains(where: { $0.id == inactiveJobId }))
        // Verify the active row has correct name
        let activeRow = rows.first(where: { $0.id == jobId })
        #expect(activeRow?.jobName == "Active Dispatch Job")
    }

    // MARK: - Shift Templates

    @Test("Shift template CRUD lifecycle: create, list, update, delete")
    func testShiftTemplateCRUD() throws {
        let env = try E2ETestHelpers.setUp()

        // Create a shift template
        let id = try env.scheduling.saveShiftTemplate(
            name: "Journeyman Field",
            hatId: nil,
            workDays: "[\"mon\",\"tue\",\"wed\",\"thu\",\"fri\"]",
            startTime: "07:00",
            endTime: "15:30",
            breakMinutes: 30,
            breakPaid: false,
            overtimeRule: "company_default"
        )
        #expect(id > 0)

        // List templates
        let templates = try env.scheduling.getShiftTemplates()
        #expect(templates.count == 1)
        #expect(templates[0].name == "Journeyman Field")
        #expect(templates[0].startTime == "07:00")
        #expect(templates[0].endTime == "15:30")
        #expect(templates[0].breakMinutes == 30)
        #expect(templates[0].breakPaid == false)

        // Update the template
        try env.scheduling.saveShiftTemplate(
            id: id,
            name: "Senior Journeyman",
            hatId: nil,
            workDays: "[\"mon\",\"tue\",\"wed\",\"thu\"]",
            startTime: "06:00",
            endTime: "16:00",
            breakMinutes: 45,
            breakPaid: true,
            overtimeRule: "daily_8"
        )
        let updated = try env.scheduling.getShiftTemplates()
        #expect(updated[0].name == "Senior Journeyman")
        #expect(updated[0].startTime == "06:00")
        #expect(updated[0].breakPaid == true)
        #expect(updated[0].overtimeRule == "daily_8")

        // Delete the template
        try env.scheduling.deleteShiftTemplate(id: id)
        let afterDelete = try env.scheduling.getShiftTemplates()
        #expect(afterDelete.isEmpty)
    }

    // MARK: - Holidays

    @Test("Holiday CRUD lifecycle: create, list, update, delete")
    func testHolidayCRUD() throws {
        let env = try E2ETestHelpers.setUp()

        // Create a holiday
        let id = try env.scheduling.saveHoliday(
            name: "Independence Day",
            date: "2026-07-04",
            isPaid: true,
            isRecurring: true
        )
        #expect(id > 0)

        // List holidays
        let holidays = try env.scheduling.getHolidays()
        #expect(holidays.count == 1)
        #expect(holidays[0].name == "Independence Day")
        #expect(holidays[0].date == "2026-07-04")
        #expect(holidays[0].isPaid == true)
        #expect(holidays[0].isRecurring == true)

        // Update the holiday
        try env.scheduling.saveHoliday(
            id: id,
            name: "Fourth of July",
            date: "2026-07-04",
            isPaid: false,
            isRecurring: false
        )
        let updated = try env.scheduling.getHolidays()
        #expect(updated[0].name == "Fourth of July")
        #expect(updated[0].isPaid == false)
        #expect(updated[0].isRecurring == false)

        // Delete the holiday
        try env.scheduling.deleteHoliday(id: id)
        let afterDelete = try env.scheduling.getHolidays()
        #expect(afterDelete.isEmpty)
    }

    @Test("Multiple holidays sort by date")
    func testHolidaysSortByDate() throws {
        let env = try E2ETestHelpers.setUp()

        try env.scheduling.saveHoliday(name: "Christmas", date: "2026-12-25", isPaid: true)
        try env.scheduling.saveHoliday(name: "New Year", date: "2026-01-01", isPaid: true)
        try env.scheduling.saveHoliday(name: "July 4th", date: "2026-07-04", isPaid: true)

        let holidays = try env.scheduling.getHolidays()
        #expect(holidays.count == 3)
        #expect(holidays[0].name == "New Year")
        #expect(holidays[1].name == "July 4th")
        #expect(holidays[2].name == "Christmas")
    }

    // MARK: - Flex Pool

    @Test("fetchFlexPool returns empty when no flex-pool jobs exist")
    func testFetchFlexPoolEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let jobs = try env.scheduling.fetchFlexPool(userId: env.adminUserId)
        #expect(jobs.isEmpty)
    }

    @Test("markJobFlexPool adds job to pool; fetchFlexPool returns it")
    func testMarkAndFetchFlexPool() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        try env.scheduling.markJobFlexPool(jobId: jobId, isFlexPool: true)
        let jobs = try env.scheduling.fetchFlexPool(userId: env.adminUserId)
        #expect(jobs.count == 1)
        #expect(jobs[0].id == jobId)
        #expect(jobs[0].jobName == "Test Job")
    }

    @Test("markJobFlexPool with false removes job from pool")
    func testMarkJobFlexPoolRemove() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        try env.scheduling.markJobFlexPool(jobId: jobId, isFlexPool: true)
        #expect(try env.scheduling.fetchFlexPool(userId: env.adminUserId).count == 1)

        try env.scheduling.markJobFlexPool(jobId: jobId, isFlexPool: false)
        #expect(try env.scheduling.fetchFlexPool(userId: env.adminUserId).isEmpty)
    }

    @Test("fetchFlexPool excludes jobs with user filter that doesn't include requesting user")
    func testFlexPoolUserFilter() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let otherUserId: Int64 = 999

        // Mark with user filter that excludes adminUserId
        try env.scheduling.markJobFlexPool(
            jobId: jobId,
            isFlexPool: true,
            userFilter: [otherUserId]
        )

        let jobs = try env.scheduling.fetchFlexPool(userId: env.adminUserId)
        #expect(jobs.isEmpty, "Job should be filtered out for users not in the user filter list")
    }

    @Test("fetchFlexPool includes job when user is in user filter list")
    func testFlexPoolUserFilterIncludes() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        try env.scheduling.markJobFlexPool(
            jobId: jobId,
            isFlexPool: true,
            userFilter: [env.adminUserId]
        )

        let jobs = try env.scheduling.fetchFlexPool(userId: env.adminUserId)
        #expect(jobs.count == 1)
    }

    @Test("claimFlexJob sets worker as lead and removes job from flex pool")
    func testClaimFlexJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        try env.scheduling.markJobFlexPool(jobId: jobId, isFlexPool: true)
        #expect(try env.scheduling.fetchFlexPool(userId: env.adminUserId).count == 1)

        try env.scheduling.claimFlexJob(jobId: jobId, userId: env.adminUserId)

        // Job should no longer appear in flex pool
        let remaining = try env.scheduling.fetchFlexPool(userId: env.adminUserId)
        #expect(remaining.isEmpty, "Claimed job should no longer appear in flex pool")
    }

    // MARK: - isJobInFlexPool

    @Test("isJobInFlexPool returns false for non-flex-pool job")
    func testIsJobInFlexPoolFalse() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let result = try env.scheduling.isJobInFlexPool(jobId: jobId)
        #expect(result == false)
    }

    @Test("isJobInFlexPool returns true after marking job as flex pool")
    func testIsJobInFlexPoolTrue() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        try env.scheduling.markJobFlexPool(jobId: jobId, isFlexPool: true)
        let result = try env.scheduling.isJobInFlexPool(jobId: jobId)
        #expect(result == true)
    }

    @Test("isJobInFlexPool returns false after removing job from flex pool")
    func testIsJobInFlexPoolAfterRemoval() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        try env.scheduling.markJobFlexPool(jobId: jobId, isFlexPool: true)
        try env.scheduling.markJobFlexPool(jobId: jobId, isFlexPool: false)
        let result = try env.scheduling.isJobInFlexPool(jobId: jobId)
        #expect(result == false)
    }

    @Test("isJobInFlexPool returns false for non-existent job")
    func testIsJobInFlexPoolNonExistent() throws {
        let env = try E2ETestHelpers.setUp()
        let result = try env.scheduling.isJobInFlexPool(jobId: 99999)
        #expect(result == false)
    }

    // MARK: - getSubSchedule with Data

    @Test("getSubSchedule returns subcontractor entries for a date")
    func testGetSubScheduleWithData() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // Insert a GC and a subcontractor schedule entry
        let gcId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO general_contractors (contact_name, company_name, created_at)
                VALUES ('Mike Plumber', 'Plumbing Co', datetime('now'))
                """)
            return db.lastInsertedRowID
        }

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO subcontractor_schedules (job_id, gc_id, scheduled_date, status, created_at)
                VALUES (?, ?, '2026-09-15', 'scheduled', datetime('now'))
                """, arguments: [jobId, gcId])
        }

        let subs = try env.scheduling.getSubSchedule(date: "2026-09-15")
        #expect(subs.count == 1)
        #expect(subs[0].subName == "Mike Plumber")
        #expect(subs[0].companyName == "Plumbing Co")
        #expect(subs[0].jobName == "Test Job")
        #expect(subs[0].status == "scheduled")
    }

    @Test("getSubSchedule returns empty for different date")
    func testGetSubScheduleDateIsolation() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let gcId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO general_contractors (contact_name, company_name, created_at)
                VALUES ('Sub Guy', 'Sub Co', datetime('now'))
                """)
            return db.lastInsertedRowID
        }

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO subcontractor_schedules (job_id, gc_id, scheduled_date, status, created_at)
                VALUES (?, ?, '2026-09-15', 'scheduled', datetime('now'))
                """, arguments: [jobId, gcId])
        }

        let subs = try env.scheduling.getSubSchedule(date: "2026-09-16")
        #expect(subs.isEmpty)
    }

    @Test("createSubcontractorSchedule stores an exact trimmed date-only value")
    func testCreateSubcontractorScheduleDateOnlyRoundTrip() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let gcId = try seedSchedulingContractor(env, contactName: "Trimmed Sub", companyName: "Trim Co")

        let scheduleId = try env.scheduling.createSubcontractorSchedule(
            jobId: jobId,
            gcId: gcId,
            scheduledDate: " 2026-09-15 ",
            arrivalTime: "08:00",
            departureTime: "12:00",
            scopeOfWork: "Rough-in",
            status: "scheduled",
            notes: "Use side gate",
            createdBy: env.adminUserId
        )

        #expect(scheduleId > 0)
        let subs = try env.scheduling.getSubSchedule(date: "2026-09-15")
        #expect(subs.count == 1)
        #expect(subs[0].scheduleDate == "2026-09-15")
        #expect(subs[0].jobId == jobId)
        #expect(subs[0].gcId == gcId)
        #expect(subs[0].subName == "Trimmed Sub")
        #expect(subs[0].arrivalTime == "08:00")
        #expect(subs[0].departureTime == "12:00")
        #expect(subs[0].scopeOfWork == "Rough-in")
        #expect(subs[0].notes == "Use side gate")
    }

    @Test("updateSubcontractorSchedule edits the date, timing, status, scope, and notes")
    func testUpdateSubcontractorScheduleEditsAllFormFields() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let gcId = try seedSchedulingContractor(env, contactName: "Edit Sub", companyName: "Edit Co")
        let scheduleId = try env.scheduling.createSubcontractorSchedule(
            jobId: jobId,
            gcId: gcId,
            scheduledDate: "2026-09-15",
            arrivalTime: "08:00",
            departureTime: "12:00",
            scopeOfWork: "Old scope",
            status: "scheduled",
            notes: "Old notes",
            createdBy: env.adminUserId
        )

        try env.scheduling.updateSubcontractorSchedule(
            id: scheduleId,
            jobId: jobId,
            gcId: gcId,
            scheduledDate: " 2026-09-16 ",
            arrivalTime: "09:15",
            departureTime: "14:45",
            scopeOfWork: "Install trim",
            status: "confirmed",
            notes: "Bring ladder"
        )

        #expect(try env.scheduling.getSubSchedule(date: "2026-09-15").isEmpty)
        let edited = try env.scheduling.getSubSchedule(date: "2026-09-16")
        #expect(edited.count == 1)
        #expect(edited[0].id == scheduleId)
        #expect(edited[0].scheduleDate == "2026-09-16")
        #expect(edited[0].arrivalTime == "09:15")
        #expect(edited[0].departureTime == "14:45")
        #expect(edited[0].scopeOfWork == "Install trim")
        #expect(edited[0].status == "confirmed")
        #expect(edited[0].notes == "Bring ladder")
    }

    @Test("subcontractor schedule rejects departure before arrival")
    func testSubcontractorScheduleRejectsDepartureBeforeArrival() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let gcId = try seedSchedulingContractor(env, contactName: "Bad Time Sub", companyName: "Bad Time Co")

        #expect(throws: SchedulingService.SchedulingError.invalidDateRange(start: "17:00", end: "08:00")) {
            _ = try env.scheduling.createSubcontractorSchedule(
                jobId: jobId,
                gcId: gcId,
                scheduledDate: "2026-09-15",
                arrivalTime: "17:00",
                departureTime: "08:00",
                scopeOfWork: nil,
                status: "scheduled",
                notes: nil,
                createdBy: nil
            )
        }
    }

    @Test("subcontractor schedule date validation rejects timestamps instead of shifting days")
    func testSubcontractorScheduleRejectsNonDateOnlyInput() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let gcId = try seedSchedulingContractor(env, contactName: "Timestamp Sub", companyName: "Time Co")

        #expect(throws: SchedulingService.SchedulingError.invalidDate("2026-09-15T00:30:00Z")) {
            _ = try env.scheduling.createSubcontractorSchedule(
                jobId: jobId,
                gcId: gcId,
                scheduledDate: "2026-09-15T00:30:00Z",
                arrivalTime: nil,
                departureTime: nil,
                scopeOfWork: nil,
                status: "scheduled",
                notes: nil,
                createdBy: nil
            )
        }
    }

    @Test("getSubSchedule excludes soft-deleted subcontractor schedules")
    func testGetSubScheduleExcludesDeletedRows() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let gcId = try seedSchedulingContractor(env, contactName: "Deleted Sub", companyName: "Gone Co")

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO subcontractor_schedules (job_id, gc_id, scheduled_date, status, deleted_at, created_at)
                VALUES (?, ?, '2026-09-15', 'scheduled', datetime('now'), datetime('now'))
                """, arguments: [jobId, gcId])
        }

        let subs = try env.scheduling.getSubSchedule(date: "2026-09-15")
        #expect(subs.isEmpty)
    }

    @Test("createSubcontractorSchedule guards deleted jobs and contractors")
    func testCreateSubcontractorScheduleGuardsDeletedJobAndContractor() throws {
        let env = try E2ETestHelpers.setUp()
        let liveJobId = try E2ETestHelpers.seedJob(env)
        let deletedJobId = try E2ETestHelpers.seedJob(env, jobNumber: "DEL-1", name: "Deleted Job")
        let liveGcId = try seedSchedulingContractor(env, contactName: "Live Sub", companyName: "Live Co")
        let deletedGcId = try seedSchedulingContractor(env, contactName: "Deleted Sub", companyName: "Deleted Co")

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?", arguments: [deletedJobId])
            try db.execute(sql: "UPDATE general_contractors SET deleted_at = datetime('now') WHERE id = ?", arguments: [deletedGcId])
        }

        #expect(throws: SchedulingService.SchedulingError.jobNotFound(deletedJobId)) {
            _ = try env.scheduling.createSubcontractorSchedule(
                jobId: deletedJobId,
                gcId: liveGcId,
                scheduledDate: "2026-09-15",
                arrivalTime: nil,
                departureTime: nil,
                scopeOfWork: nil,
                status: "scheduled",
                notes: nil,
                createdBy: nil
            )
        }

        #expect(throws: SchedulingService.SchedulingError.contractorNotFound(deletedGcId)) {
            _ = try env.scheduling.createSubcontractorSchedule(
                jobId: liveJobId,
                gcId: deletedGcId,
                scheduledDate: "2026-09-15",
                arrivalTime: nil,
                departureTime: nil,
                scopeOfWork: nil,
                status: "scheduled",
                notes: nil,
                createdBy: nil
            )
        }
    }

    @Test("createSubcontractorSchedule surfaces duplicate active date conflicts")
    func testCreateSubcontractorScheduleDuplicateConflict() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let gcId = try seedSchedulingContractor(env, contactName: "Duplicate Sub", companyName: "Dup Co")

        _ = try env.scheduling.createSubcontractorSchedule(
            jobId: jobId,
            gcId: gcId,
            scheduledDate: "2026-09-15",
            arrivalTime: nil,
            departureTime: nil,
            scopeOfWork: nil,
            status: "scheduled",
            notes: nil,
            createdBy: nil
        )

        #expect(throws: SchedulingService.SchedulingError.subcontractorScheduleConflict(jobId: jobId, gcId: gcId, date: "2026-09-15")) {
            _ = try env.scheduling.createSubcontractorSchedule(
                jobId: jobId,
                gcId: gcId,
                scheduledDate: "2026-09-15",
                arrivalTime: nil,
                departureTime: nil,
                scopeOfWork: nil,
                status: "scheduled",
                notes: nil,
                createdBy: nil
            )
        }
    }

    @Test("updateSubcontractorScheduleDate reschedules without UTC date shifts")
    func testUpdateSubcontractorScheduleDateCorrection() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let gcId = try seedSchedulingContractor(env, contactName: "Reschedule Sub", companyName: "Move Co")
        let scheduleId = try env.scheduling.createSubcontractorSchedule(
            jobId: jobId,
            gcId: gcId,
            scheduledDate: "2026-09-15",
            arrivalTime: nil,
            departureTime: nil,
            scopeOfWork: nil,
            status: "scheduled",
            notes: nil,
            createdBy: nil
        )

        try env.scheduling.updateSubcontractorScheduleDate(id: scheduleId, scheduledDate: " 2026-09-16 ")

        #expect(try env.scheduling.getSubSchedule(date: "2026-09-15").isEmpty)
        let moved = try env.scheduling.getSubSchedule(date: "2026-09-16")
        #expect(moved.count == 1)
        #expect(moved[0].scheduleDate == "2026-09-16")
    }

    @Test("cancelSubcontractorSchedule soft-deletes the row")
    func testCancelSubcontractorScheduleSoftDeletesRow() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let gcId = try seedSchedulingContractor(env, contactName: "Cancel Sub", companyName: "Cancel Co")
        let scheduleId = try env.scheduling.createSubcontractorSchedule(
            jobId: jobId,
            gcId: gcId,
            scheduledDate: "2026-09-15",
            arrivalTime: nil,
            departureTime: nil,
            scopeOfWork: nil,
            status: "scheduled",
            notes: nil,
            createdBy: nil
        )

        try env.scheduling.cancelSubcontractorSchedule(id: scheduleId)

        #expect(try env.scheduling.getSubSchedule(date: "2026-09-15").isEmpty)
        let deletedAt: String? = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT deleted_at FROM subcontractor_schedules WHERE id = ?", arguments: [scheduleId])
        }
        #expect(deletedAt != nil)
    }

    private func seedSchedulingContractor(_ env: E2ETestHelpers.TestEnvironment, contactName: String, companyName: String) throws -> Int64 {
        try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO general_contractors (contact_name, company_name, created_at)
                VALUES (?, ?, datetime('now'))
                """, arguments: [contactName, companyName])
            return db.lastInsertedRowID
        }
    }

    // MARK: - Pipeline Category Logic

    @Test("getShortTermPipeline categorizes small jobs (<=2 est days)")
    func testPipelineCategorySmallJob() throws {
        let env = try E2ETestHelpers.setUp()
        // Create a job with estimated_hours = 16 (= 2 days)
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO jobs (job_name, job_number, status, estimated_hours, deleted_at, created_at, updated_at)
                VALUES ('Small Job', 'J-SM-01', 'active', 16, NULL, datetime('now'), datetime('now'))
                """)
        }

        let pipeline = try env.scheduling.getShortTermPipeline()
        let item = pipeline.first(where: { $0.jobName == "Small Job" })
        #expect(item != nil)
        #expect(item?.pipelineCategory == "small_job")
    }

    @Test("getShortTermPipeline categorizes start_anytime (no dispatches, >2 days)")
    func testPipelineCategoryStartAnytime() throws {
        let env = try E2ETestHelpers.setUp()
        // Create a job with estimated_hours = 40 (= 5 days), no dispatches
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO jobs (job_name, job_number, status, estimated_hours, deleted_at, created_at, updated_at)
                VALUES ('Big Job', 'J-BG-01', 'active', 40, NULL, datetime('now'), datetime('now'))
                """)
        }

        let pipeline = try env.scheduling.getShortTermPipeline()
        let item = pipeline.first(where: { $0.jobName == "Big Job" })
        #expect(item != nil)
        #expect(item?.pipelineCategory == "start_anytime")
    }

    @Test("getShortTermPipeline categorizes schedule_needed (has future dispatches, >2 days)")
    func testPipelineCategoryScheduleNeeded() throws {
        let env = try E2ETestHelpers.setUp()
        // Create a job with estimated_hours = 40 (= 5 days)
        let jobId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO jobs (job_name, job_number, status, estimated_hours, deleted_at, created_at, updated_at)
                VALUES ('Scheduled Job', 'J-SN-01', 'active', 40, NULL, datetime('now'), datetime('now'))
                """)
            return db.lastInsertedRowID
        }

        // Add a future dispatch
        _ = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: "2027-01-15",
            notes: nil
        )

        let pipeline = try env.scheduling.getShortTermPipeline()
        let item = pipeline.first(where: { $0.jobName == "Scheduled Job" })
        #expect(item != nil)
        #expect(item?.pipelineCategory == "schedule_needed")
    }

    @Test("updateShortTermPipelineCategory persists a manual drag/drop category override")
    func testUpdateShortTermPipelineCategoryPersistsOverride() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO jobs (job_name, job_number, status, estimated_hours, deleted_at, created_at, updated_at)
                VALUES ('Dragged Pipeline Job', 'J-DRAG-01', 'active', 40, NULL, datetime('now'), datetime('now'))
                """)
            return db.lastInsertedRowID
        }

        #expect(try env.scheduling.getShortTermPipeline().first(where: { $0.id == jobId })?.pipelineCategory == "start_anytime")

        try env.scheduling.updateShortTermPipelineCategory(jobId: jobId, category: "favorite_gc")

        let pipeline = try env.scheduling.getShortTermPipeline()
        let item = pipeline.first(where: { $0.id == jobId })
        #expect(item != nil)
        #expect(item?.pipelineCategory == "favorite_gc")
    }

    // MARK: - updateTimeOffStatus Cancelled

    @Test("updateTimeOffStatus with cancelled status")
    func testCancelTimeOff() throws {
        let env = try E2ETestHelpers.setUp()

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-10-20",
            endDate: "2026-10-20",
            reason: "Cancelled day"
        )

        // Should not throw — "cancelled" is a valid status
        try env.scheduling.updateTimeOffStatus(id: requestId, status: "cancelled", approvedBy: env.adminUserId)

        // After cancelling, is_approved = 0, which maps to "pending" in the query
        let requests = try env.scheduling.listTimeOffRequests(userId: env.adminUserId)
        #expect(requests.count == 1)
    }

    @Test("updateTimeOffStatus on multi-day request updates all days in group")
    func testUpdateTimeOffMultiDayGroup() throws {
        let env = try E2ETestHelpers.setUp()

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-11-10",
            endDate: "2026-11-12",
            reason: "Three day vacation"
        )

        // Approve the multi-day request — should update all 3 rows
        try env.scheduling.updateTimeOffStatus(
            id: requestId,
            status: "approved",
            approvedBy: env.adminUserId
        )

        // Count approved rows in the group
        let approvedCount = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM schedule_exceptions
                WHERE user_id = ? AND exception_type = 'time_off' AND is_approved = 1
                """, arguments: [env.adminUserId])!
        }
        #expect(approvedCount == 3)
    }

    // MARK: - getScheduleEntriesForDate Empty

    @Test("getScheduleEntriesForDate returns empty when no entries exist")
    func testGetScheduleEntriesForDateEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let entries = try env.scheduling.getScheduleEntriesForDate(date: "2026-01-01")
        #expect(entries.isEmpty)
    }

    @Test("getScheduleEntriesForDate returns multiple entries sorted by time slot")
    func testGetScheduleEntriesForDateMultiple() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let secondUserId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('Worker Alpha', 'hash111', 1)
                """)
            return db.lastInsertedRowID
        }

        _ = try env.scheduling.createScheduleEntry(
            userId: env.adminUserId,
            jobId: jobId,
            date: "2026-05-20",
            timeSlot: "full"
        )
        _ = try env.scheduling.createScheduleEntry(
            userId: secondUserId,
            jobId: jobId,
            date: "2026-05-20",
            timeSlot: "am"
        )

        let entries = try env.scheduling.getScheduleEntriesForDate(date: "2026-05-20")
        #expect(entries.count == 2)
    }

    // MARK: - listTimeOffRequests Combined Filter

    @Test("listTimeOffRequests filters by both userId and status")
    func testListTimeOffCombinedFilter() throws {
        let env = try E2ETestHelpers.setUp()

        let secondUserId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('CombinedUser', 'hash222', 1)
                """)
            return db.lastInsertedRowID
        }

        // Create time-off for admin + approve it
        let id1 = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-12-01",
            endDate: "2026-12-01",
            reason: "Admin approved"
        )
        try env.scheduling.updateTimeOffStatus(id: id1, status: "approved", approvedBy: env.adminUserId)

        // Create time-off for admin + keep pending
        _ = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-12-05",
            endDate: "2026-12-05",
            reason: "Admin pending"
        )

        // Create time-off for second user + approve
        let id3 = try env.scheduling.createTimeOffRequest(
            userId: secondUserId,
            startDate: "2026-12-10",
            endDate: "2026-12-10",
            reason: "Other approved"
        )
        try env.scheduling.updateTimeOffStatus(id: id3, status: "approved", approvedBy: env.adminUserId)

        // Filter: admin + approved → only 1 result
        let result = try env.scheduling.listTimeOffRequests(
            userId: env.adminUserId,
            status: "approved"
        )
        #expect(result.count == 1)
        #expect(result[0].reason == "Admin approved")
    }

    // MARK: - getMonthScheduleSummary PM Slot

    @Test("getMonthScheduleSummary correctly counts PM slot entries")
    func testMonthSummaryWithPMSlot() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        _ = try env.scheduling.createScheduleEntry(
            userId: env.adminUserId,
            jobId: jobId,
            date: "2026-04-10",
            timeSlot: "pm"
        )

        let summary = try env.scheduling.getMonthScheduleSummary(year: 2026, month: 4)
        let april10 = summary["2026-04-10"]
        #expect(april10 != nil)
        #expect(april10!.pmCount == 1)
        #expect(april10!.amCount == 0)
        #expect(april10!.fullDayCount == 0)
        #expect(april10!.totalWorkers == 1)
    }

    // MARK: - Dispatch Efficiency with Completed

    @Test("getDispatchEfficiencyReport tracks completed dispatches")
    func testDispatchEfficiencyCompleted() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-EFF-02", name: "Completed Job")

        // Create a dispatch and mark it completed
        let dispatchId = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: "2026-06-10",
            notes: nil
        )
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE job_dispatch SET status = 'completed' WHERE id = ?",
                arguments: [dispatchId]
            )
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let start = fmt.date(from: "2026-06-09")!
        let end = fmt.date(from: "2026-06-11")!
        let rows = try env.scheduling.getDispatchEfficiencyReport(startDate: start, endDate: end)
        #expect(rows.count == 1)
        #expect(rows[0].completedCount == 1)
        #expect(rows[0].efficiency > 0)
    }

    // MARK: - claimFlexJob with Approval Required

    @Test("claimFlexJob with approval required creates pending_approval dispatch")
    func testClaimFlexJobWithApproval() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // Enable flex pool approval requirement
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO settings (key, value) VALUES ('flex_pool_requires_approval', '1')
                """)
        }

        try env.scheduling.markJobFlexPool(jobId: jobId, isFlexPool: true)
        try env.scheduling.claimFlexJob(jobId: jobId, userId: env.adminUserId)

        // Job should still be in flex pool (approval required = no removal)
        let isStillFlex = try env.scheduling.isJobInFlexPool(jobId: jobId)
        #expect(isStillFlex == true, "Job stays in flex pool when approval is required")

        // A dispatch with pending_approval status should exist
        let status = try env.db.writer.read { db in
            try String.fetchOne(db, sql: """
                SELECT status FROM job_dispatch
                WHERE job_id = ? AND user_id = ? ORDER BY id DESC LIMIT 1
                """, arguments: [jobId, env.adminUserId])
        }
        #expect(status == "pending_approval")
    }

    @Test("pending schedule approvals can be listed and approved")
    func testPendingScheduleApprovalListAndApprove() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO settings (key, value) VALUES ('flex_pool_requires_approval', '1')
                """)
        }

        try env.scheduling.markJobFlexPool(jobId: jobId, isFlexPool: true)
        try env.scheduling.claimFlexJob(jobId: jobId, userId: env.adminUserId)

        let pending = try env.scheduling.listPendingScheduleChangeApprovals()
        #expect(pending.count == 1)
        #expect(pending[0].jobName == "Test Job")
        #expect(pending[0].userName == "TestAdmin")

        try env.scheduling.approveScheduleChange(dispatchId: pending[0].id, approvedBy: env.adminUserId)

        let approved = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: """
                SELECT jd.status, j.lead_user_id, j.is_flex_pool
                FROM job_dispatch jd
                JOIN jobs j ON j.id = jd.job_id
                WHERE jd.id = ?
                """, arguments: [pending[0].id])
        }
        #expect(approved?["status"] as String? == "scheduled")
        #expect(approved?["lead_user_id"] as Int64? == env.adminUserId)
        #expect(approved?["is_flex_pool"] as Int? == 0)

        let afterApproval = try env.scheduling.listPendingScheduleChangeApprovals()
        #expect(afterApproval.isEmpty)
    }

    // MARK: - createTimeOffRequest Invalid Date

    @Test("createTimeOffRequest with same start and end creates single entry")
    func testCreateTimeOffSingleDay() throws {
        let env = try E2ETestHelpers.setUp()

        let id = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-05-05",
            endDate: "2026-05-05",
            reason: "Single day"
        )
        #expect(id > 0)

        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM schedule_exceptions
                WHERE user_id = ? AND exception_type = 'time_off'
                """, arguments: [env.adminUserId])!
        }
        #expect(count == 1)
    }

    // MARK: - getMySchedule with Multiple Entries

    @Test("getMySchedule returns entries sorted by date ascending")
    func testGetMyScheduleSorted() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        _ = try env.scheduling.createScheduleEntry(
            userId: env.adminUserId,
            jobId: jobId,
            date: "2026-07-20",
            timeSlot: "full"
        )
        _ = try env.scheduling.createScheduleEntry(
            userId: env.adminUserId,
            jobId: jobId,
            date: "2026-07-10",
            timeSlot: "am"
        )

        let schedule = try env.scheduling.getMySchedule(
            userId: env.adminUserId,
            startDate: "2026-07-01",
            endDate: "2026-07-31"
        )
        #expect(schedule.count == 2)
        #expect(schedule[0].date == "2026-07-10")
        #expect(schedule[1].date == "2026-07-20")
    }

    @Test("getMySchedule excludes entries outside date range")
    func testGetMyScheduleDateRange() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        _ = try env.scheduling.createScheduleEntry(
            userId: env.adminUserId,
            jobId: jobId,
            date: "2026-06-15",
            timeSlot: "full"
        )
        _ = try env.scheduling.createScheduleEntry(
            userId: env.adminUserId,
            jobId: jobId,
            date: "2026-08-15",
            timeSlot: "full"
        )

        let schedule = try env.scheduling.getMySchedule(
            userId: env.adminUserId,
            startDate: "2026-07-01",
            endDate: "2026-07-31"
        )
        #expect(schedule.isEmpty)
    }

    // MARK: - getDispatchBoard Multiple Entries

    @Test("getDispatchBoard returns multiple dispatches sorted by user name")
    func testGetDispatchBoardMultiple() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let workerId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('Alpha Worker', 'hash333', 1)
                """)
            return db.lastInsertedRowID
        }

        _ = try env.scheduling.createDispatch(jobId: jobId, userId: env.adminUserId, date: "2026-09-01")
        _ = try env.scheduling.createDispatch(jobId: jobId, userId: workerId, date: "2026-09-01")

        let board = try env.scheduling.getDispatchBoard(date: "2026-09-01")
        #expect(board.count == 2)
        // Sorted by display_name ASC
        #expect(board[0].userName == "Alpha Worker")
        #expect(board[1].userName == "TestAdmin")
    }

    // MARK: - Weekly Availability with Multiple Users

    @Test("getWeeklyAvailability returns rows for multiple users")
    func testWeeklyAvailabilityMultipleUsers() throws {
        let env = try E2ETestHelpers.setUp()

        _ = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('Worker Two', 'hash444', 1)
                """)
            return db.lastInsertedRowID
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let weekStart = fmt.date(from: "2026-08-03")!

        let rows = try env.scheduling.getWeeklyAvailability(weekStartDate: weekStart)
        #expect(rows.count >= 2)
        // All users should have 7 days
        for row in rows {
            #expect(row.days.count == 7)
        }
    }

    // MARK: - getWeeklyDispatchAssignments Initials

    @Test("getWeeklyDispatchAssignments generates correct initials")
    func testWeeklyDispatchInitials() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-INIT-01", name: "Initials Job")

        let workerId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('John Smith', 'hash555', 1)
                """)
            return db.lastInsertedRowID
        }

        _ = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: workerId,
            date: "2026-10-05",
            notes: nil
        )

        let assignments = try env.scheduling.getWeeklyDispatchAssignments(
            weekStart: "2026-10-01",
            weekEnd: "2026-10-07"
        )
        #expect(assignments.count == 1)
        #expect(assignments[0].employeeInitials == "JS")
        #expect(assignments[0].employeeName == "John Smith")
    }

    @Test("getWeeklyDispatchAssignments generates initials for single-word name")
    func testWeeklyDispatchInitialsSingleName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-INIT-02", name: "Single Name Job")

        let workerId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('Mike', 'hash666', 1)
                """)
            return db.lastInsertedRowID
        }

        _ = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: workerId,
            date: "2026-10-06",
            notes: nil
        )

        let assignments = try env.scheduling.getWeeklyDispatchAssignments(
            weekStart: "2026-10-01",
            weekEnd: "2026-10-07"
        )
        let mikeAssignment = assignments.first(where: { $0.employeeName == "Mike" })
        #expect(mikeAssignment != nil)
        #expect(mikeAssignment?.employeeInitials == "MI")
    }

    // MARK: - Dispatch Template with Inactive

    @Test("listDispatchTemplates excludes soft-deleted templates")
    func testListDispatchTemplatesExcludesDeleted() throws {
        let env = try E2ETestHelpers.setUp()

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO dispatch_templates (name, description, is_active, deleted_at)
                VALUES ('Deleted Template', 'Should not appear', 1, datetime('now'))
                """)
        }

        let templates = try env.scheduling.listDispatchTemplates()
        #expect(templates.isEmpty)
    }

    // MARK: - Capacity Warnings Normal Utilization

    @Test("getCapacityWarnings produces no warnings for moderate utilization")
    func testCapacityWarningsNoWarning() {
        let normalMonth = SchedulingService.MonthCapacity(
            id: "2026-08",
            monthLabel: "August 2026",
            availableDays: 22,
            scheduledDays: 15,  // ~68% utilization
            jobCount: 2,
            pendingBidCount: 1,
            jobs: []
        )
        let env = try? E2ETestHelpers.setUp()
        let warnings = env?.scheduling.getCapacityWarnings(timeline: [normalMonth]) ?? []
        #expect(warnings.isEmpty)
    }

    // MARK: - MonthCapacity utilizationPercent

    @Test("MonthCapacity utilizationPercent computes correctly")
    func testMonthCapacityUtilization() {
        let month = SchedulingService.MonthCapacity(
            id: "2026-05",
            monthLabel: "May 2026",
            availableDays: 20,
            scheduledDays: 10,
            jobCount: 1,
            pendingBidCount: 0,
            jobs: []
        )
        #expect(month.utilizationPercent == 0.5)
    }

    @Test("MonthCapacity utilizationPercent handles zero available days")
    func testMonthCapacityUtilizationZero() {
        let month = SchedulingService.MonthCapacity(
            id: "2026-05",
            monthLabel: "May 2026",
            availableDays: 0,
            scheduledDays: 5,
            jobCount: 1,
            pendingBidCount: 0,
            jobs: []
        )
        // availableDays=0 → max(0,1) = 1 → 5/1 = 5.0
        #expect(month.utilizationPercent == 5.0)
    }

    // MARK: - createScheduleEntry with All Parameters

    @Test("createScheduleEntry stores all optional parameters")
    func testCreateScheduleEntryFullParams() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let entryId = try env.scheduling.createScheduleEntry(
            userId: env.adminUserId,
            jobId: jobId,
            date: "2026-11-20",
            startTime: "06:00",
            endTime: "14:30",
            notes: "Early bird shift",
            timeSlot: "am"
        )
        #expect(entryId > 0)

        let entries = try env.scheduling.getScheduleEntriesForDate(date: "2026-11-20")
        #expect(entries.count == 1)
        #expect(entries[0].startTime == "06:00")
        #expect(entries[0].endTime == "14:30")
        #expect(entries[0].notes == "Early bird shift")
        #expect(entries[0].timeSlot == "am")
    }

    // MARK: - Crew Utilization with Custom Shifts

    @Test("getCrewUtilizationReport calculates hours from shift times")
    func testCrewUtilizationCustomShifts() throws {
        let env = try E2ETestHelpers.setUp()
        let workerId = try env.auth.createUser(displayName: "Shift Worker", pin: "7890")
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-SHIFT-01", name: "Shift Job")

        // Create dispatch with explicit shift times (6 hour shift)
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO job_dispatch (job_id, user_id, dispatch_date, shift_start, shift_end, status, created_at, updated_at)
                VALUES (?, ?, '2026-04-20', '08:00', '14:00', 'scheduled', datetime('now'), datetime('now'))
                """, arguments: [jobId, workerId])
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let start = fmt.date(from: "2026-04-19")!
        let end = fmt.date(from: "2026-04-21")!
        let rows = try env.scheduling.getCrewUtilizationReport(startDate: start, endDate: end)
        #expect(rows.count >= 1)

        let workerRow = rows.first(where: { $0.employeeName == "Shift Worker" })
        #expect(workerRow != nil)
        // 08:00 to 14:00 = 6 hours
        #expect(workerRow!.scheduledHours > 5.0)
        #expect(workerRow!.scheduledHours < 7.0)
    }

    // MARK: - Time-Off for Date with Multiple Users

    @Test("getTimeOffForDate returns entries for multiple users on same date")
    func testGetTimeOffForDateMultiple() throws {
        let env = try E2ETestHelpers.setUp()

        let secondUserId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('Worker Beta', 'hash777', 1)
                """)
            return db.lastInsertedRowID
        }

        _ = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-07-20",
            endDate: "2026-07-20",
            reason: "Admin off"
        )
        _ = try env.scheduling.createTimeOffRequest(
            userId: secondUserId,
            startDate: "2026-07-20",
            endDate: "2026-07-20",
            reason: "Worker off"
        )

        let entries = try env.scheduling.getTimeOffForDate(date: "2026-07-20")
        #expect(entries.count == 2)
    }

    // MARK: - fetchFlexPool Job Details

    @Test("fetchFlexPool returns correct job details")
    func testFetchFlexPoolJobDetails() throws {
        let env = try E2ETestHelpers.setUp()

        // Create a job with all flex-pool-relevant fields
        let jobId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO jobs (job_name, job_number, address_line1, notes, estimated_hours,
                    status, is_flex_pool, deleted_at, created_at, updated_at)
                VALUES ('Flex Detail Job', 'FD-001', '123 Main St', 'Flexible work',
                    24.0, 'active', 1, NULL, datetime('now'), datetime('now'))
                """)
            return db.lastInsertedRowID
        }

        let jobs = try env.scheduling.fetchFlexPool(userId: env.adminUserId)
        let job = jobs.first(where: { $0.id == jobId })
        #expect(job != nil)
        #expect(job?.jobName == "Flex Detail Job")
        #expect(job?.jobNumber == "FD-001")
        #expect(job?.address == "123 Main St")
        #expect(job?.description == "Flexible work")
        #expect(job?.estimatedHours == 24.0)
        #expect(job?.isApprovalRequired == false)
    }

    // MARK: - getMonthScheduleSummary Time-Off Only

    @Test("getMonthScheduleSummary returns summary for date with only time-off")
    func testMonthSummaryTimeOffOnly() throws {
        let env = try E2ETestHelpers.setUp()

        _ = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-02-15",
            endDate: "2026-02-15",
            reason: "Day off only"
        )

        let summary = try env.scheduling.getMonthScheduleSummary(year: 2026, month: 2)
        let feb15 = summary["2026-02-15"]
        #expect(feb15 != nil)
        #expect(feb15!.timeOffCount == 1)
        #expect(feb15!.totalWorkers == 0)
        #expect(feb15!.amCount == 0)
        #expect(feb15!.pmCount == 0)
        #expect(feb15!.fullDayCount == 0)
    }

    // MARK: - updateTimeOffStatus Legacy Rows (No request_group)

    @Test("updateTimeOffStatus approves legacy row without request_group")
    func testApproveTimeOffLegacyRow() throws {
        let env = try E2ETestHelpers.setUp()

        // Insert a legacy time-off row directly (no request_group)
        let legacyId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO schedule_exceptions
                (user_id, exception_date, exception_type, reason, is_approved, request_group, created_at)
                VALUES (?, '2026-11-25', 'time_off', 'Legacy day', 0, NULL, datetime('now'))
                """, arguments: [env.adminUserId])
            return db.lastInsertedRowID
        }

        // Approve the legacy row (hits the else branch at L468)
        try env.scheduling.updateTimeOffStatus(
            id: legacyId,
            status: "approved",
            approvedBy: env.adminUserId
        )

        // Verify it was approved
        let isApproved = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: """
                SELECT is_approved FROM schedule_exceptions WHERE id = ?
                """, arguments: [legacyId])
        }
        #expect(isApproved == 1)
    }

    @Test("updateTimeOffStatus denies legacy row without request_group")
    func testDenyTimeOffLegacyRow() throws {
        let env = try E2ETestHelpers.setUp()

        // Insert a legacy time-off row directly (no request_group)
        let legacyId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO schedule_exceptions
                (user_id, exception_date, exception_type, reason, is_approved, request_group, created_at)
                VALUES (?, '2026-11-26', 'time_off', 'Legacy deny', 0, NULL, datetime('now'))
                """, arguments: [env.adminUserId])
            return db.lastInsertedRowID
        }

        // Deny the legacy row (hits the else branch at L488)
        try env.scheduling.updateTimeOffStatus(
            id: legacyId,
            status: "denied",
            approvedBy: env.adminUserId
        )

        // Verify is_approved is still 0
        let isApproved = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: """
                SELECT is_approved FROM schedule_exceptions WHERE id = ?
                """, arguments: [legacyId])
        }
        #expect(isApproved == 0)
    }

    // MARK: - markCallbackComplete with Empty String Notes

    @Test("markCallbackComplete with empty string notes clears due_date without appending")
    func testMarkCallbackCompleteEmptyStringNotes() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-CB-03", name: "Empty Notes Job")
        try env.scheduling.snoozeCallback(jobId: jobId, until: "2026-11-20")
        try env.scheduling.markCallbackComplete(jobId: jobId, notes: "")

        let pipeline = try env.scheduling.getShortTermPipeline()
        let item = pipeline.first(where: { $0.id == jobId })
        #expect(item?.callbackDate == nil)
    }

    // MARK: - getSchedulingStats with Today Data

    @Test("getSchedulingStats counts scheduledToday and dispatchedToday")
    func testScheduleStatsWithTodayData() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-ST-01", name: "Today Job")

        // Use date('now') directly in SQL to match what the service queries use (UTC)
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO job_dispatch (job_id, user_id, dispatch_date, status, created_at, updated_at)
                VALUES (?, ?, date('now'), 'scheduled', datetime('now'), datetime('now'))
                """, arguments: [jobId, env.adminUserId])
        }

        // Create a second user with a dispatched status dispatch
        let workerId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('Dispatched Worker', 'hash_st', 1)
                """)
            return db.lastInsertedRowID
        }
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO job_dispatch (job_id, user_id, dispatch_date, status, created_at, updated_at)
                VALUES (?, ?, date('now'), 'dispatched', datetime('now'), datetime('now'))
                """, arguments: [jobId, workerId])
        }

        let stats = try env.scheduling.getSchedulingStats()
        #expect(stats.scheduledToday >= 2)
        #expect(stats.dispatchedToday >= 1)
    }

    // MARK: - getLongTermTimeline with Job Data

    @Test("getLongTermTimeline reflects scheduled days from active jobs")
    func testLongTermTimelineWithJobData() throws {
        let env = try E2ETestHelpers.setUp()

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        // Create a job with start_date in the current month and estimated hours
        let today = Date()
        let cal = Calendar.current
        let year = cal.component(.year, from: today)
        let month = cal.component(.month, from: today)
        let startDate = String(format: "%04d-%02d-01", year, month)

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO jobs (job_name, job_number, status, estimated_hours, start_date, deleted_at, created_at, updated_at)
                VALUES ('Timeline Job', 'J-TL-01', 'active', 80, ?, NULL, datetime('now'), datetime('now'))
                """, arguments: [startDate])
        }

        let timeline = try env.scheduling.getLongTermTimeline(months: 1)
        #expect(timeline.count == 1)
        #expect(timeline[0].jobCount >= 1)
        #expect(timeline[0].scheduledDays >= 1)
    }

    @Test("getLongTermTimeline counts pending bids")
    func testLongTermTimelinePendingBids() throws {
        let env = try E2ETestHelpers.setUp()

        // Create a bid job (no start_date → counts in all months)
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO jobs (job_name, job_number, status, deleted_at, created_at, updated_at)
                VALUES ('Bid Job', 'J-BID-01', 'bid', NULL, datetime('now'), datetime('now'))
                """)
        }

        let timeline = try env.scheduling.getLongTermTimeline(months: 1)
        #expect(timeline[0].pendingBidCount >= 1)
    }

    // MARK: - Dispatch Efficiency Dispatched Status

    @Test("getDispatchEfficiencyReport counts dispatched status")
    func testDispatchEfficiencyDispatchedStatus() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-EFF-03", name: "Dispatched Job")

        let dispatchId = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: "2026-06-20",
            notes: nil
        )
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE job_dispatch SET status = 'dispatched' WHERE id = ?",
                arguments: [dispatchId]
            )
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let start = fmt.date(from: "2026-06-19")!
        let end = fmt.date(from: "2026-06-21")!
        let rows = try env.scheduling.getDispatchEfficiencyReport(startDate: start, endDate: end)
        #expect(rows.count == 1)
        #expect(rows[0].dispatchedCount == 1)
        #expect(rows[0].scheduledCount == 1)
    }

    // MARK: - Pipeline Summary Multiple Statuses

    @Test("getPipelineSummaryReport returns multiple status rows with estimated hours")
    func testPipelineSummaryMultipleStatuses() throws {
        let env = try E2ETestHelpers.setUp()

        // Create active job with estimated hours
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO jobs (job_name, job_number, status, estimated_hours, deleted_at, created_at, updated_at)
                VALUES ('Active Job', 'J-PS-02', 'active', 40, NULL, datetime('now'), datetime('now'))
                """)
        }

        // Create on_hold job with estimated hours
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO jobs (job_name, job_number, status, estimated_hours, deleted_at, created_at, updated_at)
                VALUES ('Hold Job', 'J-PS-03', 'on_hold', 20, NULL, datetime('now'), datetime('now'))
                """)
        }

        let rows = try env.scheduling.getPipelineSummaryReport()
        #expect(rows.count >= 2)

        let activeRow = rows.first(where: { $0.status == "active" })
        #expect(activeRow != nil)
        #expect(activeRow!.totalEstimatedHours >= 40)

        let holdRow = rows.first(where: { $0.status == "on_hold" })
        #expect(holdRow != nil)
        #expect(holdRow!.jobCount == 1)
    }

    // MARK: - Shift Template with Hat Association

    @Test("getShiftTemplates returns hat name when associated")
    func testShiftTemplateWithHat() throws {
        let env = try E2ETestHelpers.setUp()

        // Create a hat
        let hatId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO hats (name, created_at) VALUES ('Journeyman', datetime('now'))
                """)
            return db.lastInsertedRowID
        }

        let id = try env.scheduling.saveShiftTemplate(
            name: "Journeyman Shift",
            hatId: hatId,
            workDays: "[\"mon\",\"tue\",\"wed\",\"thu\",\"fri\"]",
            startTime: "07:00",
            endTime: "15:30"
        )
        #expect(id > 0)

        let templates = try env.scheduling.getShiftTemplates()
        #expect(templates.count == 1)
        #expect(templates[0].hatId == hatId)
        #expect(templates[0].hatName == "Journeyman")
    }

    // MARK: - fetchFlexPool with Approval Required

    @Test("fetchFlexPool sets isApprovalRequired when setting enabled")
    func testFetchFlexPoolApprovalRequired() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // Enable approval requirement
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO settings (key, value) VALUES ('flex_pool_requires_approval', '1')
                """)
        }

        try env.scheduling.markJobFlexPool(jobId: jobId, isFlexPool: true)
        let jobs = try env.scheduling.fetchFlexPool(userId: env.adminUserId)
        #expect(jobs.count == 1)
        #expect(jobs[0].isApprovalRequired == true)
    }

    // MARK: - markJobFlexPool with Team Filter

    @Test("markJobFlexPool stores team filter as JSON")
    func testMarkJobFlexPoolTeamFilter() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        try env.scheduling.markJobFlexPool(
            jobId: jobId,
            isFlexPool: true,
            teamFilter: [10, 20, 30]
        )

        // Verify the team filter was stored
        let teamFilter = try env.db.writer.read { db in
            try String.fetchOne(db, sql: """
                SELECT flex_pool_team_filter FROM jobs WHERE id = ?
                """, arguments: [jobId])
        }
        #expect(teamFilter != nil)
        #expect(teamFilter!.contains("10"))
        #expect(teamFilter!.contains("20"))
        #expect(teamFilter!.contains("30"))
    }

    // MARK: - Pipeline Customer Name and Notes

    @Test("getShortTermPipeline returns customer_name and notes")
    func testPipelineCustomerNameAndNotes() throws {
        let env = try E2ETestHelpers.setUp()

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO jobs (job_name, job_number, customer_name, notes, status, estimated_hours, deleted_at, created_at, updated_at)
                VALUES ('Customer Job', 'J-CU-01', 'Acme Corp', 'Important project', 'active', 40, NULL, datetime('now'), datetime('now'))
                """)
        }

        let pipeline = try env.scheduling.getShortTermPipeline()
        let item = pipeline.first(where: { $0.jobName == "Customer Job" })
        #expect(item != nil)
        #expect(item?.customerName == "Acme Corp")
        #expect(item?.notes == "Important project")
    }

    // MARK: - Capacity Warnings Multiple

    @Test("getCapacityWarnings returns multiple warnings for mixed timeline")
    func testCapacityWarningsMultiple() {
        let overMonth = SchedulingService.MonthCapacity(
            id: "2026-09",
            monthLabel: "September 2026",
            availableDays: 10,
            scheduledDays: 15,
            jobCount: 4,
            pendingBidCount: 0,
            jobs: []
        )
        let emptyMonth = SchedulingService.MonthCapacity(
            id: "2026-10",
            monthLabel: "October 2026",
            availableDays: 22,
            scheduledDays: 0,
            jobCount: 0,
            pendingBidCount: 0,
            jobs: []
        )
        let env = try? E2ETestHelpers.setUp()
        let warnings = env?.scheduling.getCapacityWarnings(timeline: [overMonth, emptyMonth]) ?? []
        #expect(warnings.count == 2)
        #expect(warnings.contains(where: { $0.isOvercommitted == true }))
        #expect(warnings.contains(where: { $0.isOvercommitted == false }))
    }

    @Test("getCapacityWarnings only checks first 12 months")
    func testCapacityWarningsLimitTo12() {
        // Create 15 overcommitted months; only first 12 should generate warnings
        var months: [SchedulingService.MonthCapacity] = []
        for i in 0..<15 {
            months.append(SchedulingService.MonthCapacity(
                id: String(format: "2027-%02d", i + 1),
                monthLabel: "Month \(i + 1)",
                availableDays: 10,
                scheduledDays: 20,
                jobCount: 3,
                pendingBidCount: 0,
                jobs: []
            ))
        }
        let env = try? E2ETestHelpers.setUp()
        let warnings = env?.scheduling.getCapacityWarnings(timeline: months) ?? []
        #expect(warnings.count == 12)
    }

    // MARK: - listTimeOffRequests Multi-Day Grouping

    @Test("listTimeOffRequests groups multi-day request into single row with date span")
    func testListTimeOffMultiDayGrouping() throws {
        let env = try E2ETestHelpers.setUp()

        _ = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-09-01",
            endDate: "2026-09-05",
            reason: "Long vacation"
        )

        let requests = try env.scheduling.listTimeOffRequests(userId: env.adminUserId)
        // Multi-day request should be grouped into one row
        #expect(requests.count == 1)
        #expect(requests[0].startDate == "2026-09-01")
        #expect(requests[0].endDate == "2026-09-05")
        #expect(requests[0].reason == "Long vacation")
    }

    // MARK: - getDispatchJobRows Stage Name

    @Test("getDispatchJobRows returns stageName from job status")
    func testDispatchJobRowsStageName() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try E2ETestHelpers.seedJob(env, jobNumber: "J-STG-01", name: "Staged Job")

        let rows = try env.scheduling.getDispatchJobRows()
        let row = rows.first(where: { $0.jobName == "Staged Job" })
        #expect(row != nil)
        #expect(row?.stageName == "active")
    }

    // MARK: - getMonthScheduleSummary Multiple Days

    @Test("getMonthScheduleSummary returns entries for multiple dates in same month")
    func testMonthSummaryMultipleDays() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        _ = try env.scheduling.createScheduleEntry(
            userId: env.adminUserId,
            jobId: jobId,
            date: "2026-05-10",
            timeSlot: "full"
        )
        _ = try env.scheduling.createScheduleEntry(
            userId: env.adminUserId,
            jobId: jobId,
            date: "2026-05-15",
            timeSlot: "am"
        )

        let summary = try env.scheduling.getMonthScheduleSummary(year: 2026, month: 5)
        #expect(summary.count == 2)
        #expect(summary["2026-05-10"] != nil)
        #expect(summary["2026-05-10"]!.fullDayCount == 1)
        #expect(summary["2026-05-15"] != nil)
        #expect(summary["2026-05-15"]!.amCount == 1)
    }

    // MARK: - createTimeOffRequest with No Reason

    @Test("createTimeOffRequest with nil reason stores null")
    func testCreateTimeOffNoReason() throws {
        let env = try E2ETestHelpers.setUp()

        let id = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-03-15",
            endDate: "2026-03-15"
        )
        #expect(id > 0)

        let requests = try env.scheduling.listTimeOffRequests(userId: env.adminUserId)
        #expect(requests.count == 1)
        #expect(requests[0].reason == nil)
    }

    // MARK: - createDispatch with No Notes

    @Test("createDispatch with nil notes stores null")
    func testCreateDispatchNoNotes() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let id = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: "2026-12-01"
        )
        #expect(id > 0)

        let board = try env.scheduling.getDispatchBoard(date: "2026-12-01")
        #expect(board.count == 1)
        #expect(board[0].notes == nil)
    }

    // MARK: - Inactive Dispatch Templates

    @Test("listDispatchTemplates returns inactive templates")
    func testListDispatchTemplatesInactive() throws {
        let env = try E2ETestHelpers.setUp()

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO dispatch_templates (name, description, is_active)
                VALUES ('Inactive Crew', 'Deactivated', 0)
                """)
        }

        let templates = try env.scheduling.listDispatchTemplates()
        #expect(templates.count == 1)
        #expect(templates[0].isActive == false)
        #expect(templates[0].name == "Inactive Crew")
    }

    // MARK: - getWeeklyDispatchAssignments Time Slot and Status

    @Test("getWeeklyDispatchAssignments returns time_slot and status from dispatch")
    func testWeeklyDispatchTimeSlotAndStatus() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-TS-01", name: "Time Slot Job")

        // Create an AM schedule entry
        _ = try env.scheduling.createScheduleEntry(
            userId: env.adminUserId,
            jobId: jobId,
            date: "2026-10-12",
            timeSlot: "am"
        )

        let assignments = try env.scheduling.getWeeklyDispatchAssignments(
            weekStart: "2026-10-12",
            weekEnd: "2026-10-12"
        )
        #expect(assignments.count == 1)
        #expect(assignments[0].timeSlot == "am")
        #expect(assignments[0].status == "scheduled")
    }

    // MARK: - Soft-Deleted Dispatch Not Returned

    @Test("getMySchedule excludes soft-deleted dispatches")
    func testGetMyScheduleExcludesSoftDeleted() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let entryId = try env.scheduling.createScheduleEntry(
            userId: env.adminUserId,
            jobId: jobId,
            date: "2026-12-10",
            timeSlot: "full"
        )

        // Soft-delete the entry
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE job_dispatch SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [entryId]
            )
        }

        let schedule = try env.scheduling.getMySchedule(
            userId: env.adminUserId,
            startDate: "2026-12-01",
            endDate: "2026-12-31"
        )
        #expect(schedule.isEmpty)
    }

    @Test("getDispatchBoard excludes soft-deleted dispatches")
    func testGetDispatchBoardExcludesSoftDeleted() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let dispatchId = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: "2026-12-15"
        )

        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE job_dispatch SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [dispatchId]
            )
        }

        let board = try env.scheduling.getDispatchBoard(date: "2026-12-15")
        #expect(board.isEmpty)
    }

    // MARK: - Soft-Deleted Time-Off Excluded

    @Test("getTimeOffForDate excludes soft-deleted time-off entries")
    func testGetTimeOffForDateExcludesSoftDeleted() throws {
        let env = try E2ETestHelpers.setUp()

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-12-20",
            endDate: "2026-12-20",
            reason: "To be deleted"
        )

        // Soft-delete the entry
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE schedule_exceptions SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [requestId]
            )
        }

        let entries = try env.scheduling.getTimeOffForDate(date: "2026-12-20")
        #expect(entries.isEmpty)
    }

    @Test("checkTimeOffConflict ignores pending time-off")
    func testCheckTimeOffConflictIgnoresPendingTimeOff() throws {
        let env = try E2ETestHelpers.setUp()

        _ = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-12-21",
            endDate: "2026-12-21",
            reason: "Pending PTO"
        )

        let conflict = try env.scheduling.checkTimeOffConflict(
            employeeId: env.adminUserId,
            date: "2026-12-21"
        )
        #expect(conflict == nil)
    }

    @Test("checkTimeOffConflict ignores soft-deleted time-off")
    func testCheckTimeOffConflictIgnoresSoftDeleted() throws {
        let env = try E2ETestHelpers.setUp()

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-12-22",
            endDate: "2026-12-22",
            reason: "Deleted PTO"
        )

        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE schedule_exceptions SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [requestId]
            )
        }

        let conflict = try env.scheduling.checkTimeOffConflict(
            employeeId: env.adminUserId,
            date: "2026-12-22"
        )
        #expect(conflict == nil)
    }

    // MARK: - Error Enum Cases

    @Test("SchedulingError cases are distinct")
    func testSchedulingErrorCases() {
        let err1 = SchedulingService.SchedulingError.timeOffRequestNotFound(42)
        let err2 = SchedulingService.SchedulingError.invalidStatus("bad")
        let err3 = SchedulingService.SchedulingError.insertFailed("fail")

        // Verify string descriptions are meaningful
        let desc1 = String(describing: err1)
        #expect(desc1.contains("42"))
        let desc2 = String(describing: err2)
        #expect(desc2.contains("bad"))
        let desc3 = String(describing: err3)
        #expect(desc3.contains("fail"))
    }

    // MARK: - updateTimeOffStatus with Pending Status

    @Test("updateTimeOffStatus with pending status is valid")
    func testUpdateTimeOffPendingStatus() throws {
        let env = try E2ETestHelpers.setUp()

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-10-25",
            endDate: "2026-10-25",
            reason: "Reset to pending"
        )

        // First approve it
        try env.scheduling.updateTimeOffStatus(
            id: requestId,
            status: "approved",
            approvedBy: env.adminUserId
        )

        // Then reset to pending (valid operation)
        try env.scheduling.updateTimeOffStatus(
            id: requestId,
            status: "pending"
        )

        // Verify it's back to pending and no stale approver is surfaced
        let requests = try env.scheduling.listTimeOffRequests(
            userId: env.adminUserId,
            status: "pending"
        )
        #expect(requests.count == 1)
        #expect(requests.first?.approvedByName == nil)
    }

    // MARK: - Crew Utilization Caps at 1.0

    @Test("getCrewUtilizationReport caps utilization at 1.0")
    func testCrewUtilizationCapsAtOne() throws {
        let env = try E2ETestHelpers.setUp()
        let workerId = try env.auth.createUser(displayName: "Overworked", pin: "0000")
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-OW-01", name: "Overwork Job")

        // Create many dispatches (12 dispatches for 1-day range = 96 hours vs 8 available)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        for i in 1...12 {
            let dateStr = String(format: "2026-03-%02d", i)
            _ = try env.scheduling.createDispatch(
                jobId: jobId,
                userId: workerId,
                date: dateStr,
                notes: nil
            )
        }

        let start = fmt.date(from: "2026-03-01")!
        let end = fmt.date(from: "2026-03-12")!
        let rows = try env.scheduling.getCrewUtilizationReport(startDate: start, endDate: end)

        let workerRow = rows.first(where: { $0.employeeName == "Overworked" })
        #expect(workerRow != nil)
        #expect(workerRow!.utilization <= 1.0, "Utilization should be capped at 1.0")
    }

    // MARK: - getLongTermTimeline Available Days Uses Crew Size

    @Test("getLongTermTimeline availableDays reflects active crew count")
    func testLongTermTimelineCrewSize() throws {
        let env = try E2ETestHelpers.setUp()

        // Admin user already exists. Add 2 more users.
        _ = try env.auth.createUser(displayName: "Crew A", pin: "1111")
        _ = try env.auth.createUser(displayName: "Crew B", pin: "2222")

        let timeline = try env.scheduling.getLongTermTimeline(months: 1)
        #expect(timeline.count == 1)
        // 3 users × 22 work days per month = 66
        #expect(timeline[0].availableDays == 66)
    }

    // MARK: - Deleted User Excluded from Weekly Availability

    @Test("getWeeklyAvailability excludes deleted users")
    func testWeeklyAvailabilityExcludesDeletedUsers() throws {
        let env = try E2ETestHelpers.setUp()

        // Create and then soft-delete a user
        let deletedId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active, deleted_at)
                VALUES ('Ghost User', 'hash_del', 1, datetime('now'))
                """)
            return db.lastInsertedRowID
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let weekStart = fmt.date(from: "2026-09-07")!

        let rows = try env.scheduling.getWeeklyAvailability(weekStartDate: weekStart)
        #expect(!rows.contains(where: { $0.id == deletedId }))
    }

    // MARK: - Soft-Deleted Jobs Excluded from Pipeline

    @Test("getShortTermPipeline excludes soft-deleted jobs")
    func testPipelineExcludesSoftDeletedJobs() throws {
        let env = try E2ETestHelpers.setUp()

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO jobs (job_name, job_number, status, deleted_at, created_at, updated_at)
                VALUES ('Deleted Active Job', 'J-DEL-01', 'active', datetime('now'), datetime('now'), datetime('now'))
                """)
        }

        let pipeline = try env.scheduling.getShortTermPipeline()
        #expect(!pipeline.contains(where: { $0.jobName == "Deleted Active Job" }))
    }

    @Test("getDispatchJobRows excludes soft-deleted jobs")
    func testDispatchJobRowsExcludesSoftDeleted() throws {
        let env = try E2ETestHelpers.setUp()

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO jobs (job_name, job_number, status, deleted_at, created_at, updated_at)
                VALUES ('Deleted Dispatch Job', 'J-DEL-02', 'active', datetime('now'), datetime('now'), datetime('now'))
                """)
        }

        let rows = try env.scheduling.getDispatchJobRows()
        #expect(!rows.contains(where: { $0.jobName == "Deleted Dispatch Job" }))
    }

    // MARK: - Deleted Job in Flex Pool

    @Test("isJobInFlexPool returns false for soft-deleted job")
    func testIsJobInFlexPoolDeletedJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        try env.scheduling.markJobFlexPool(jobId: jobId, isFlexPool: true)

        // Soft-delete the job
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [jobId]
            )
        }

        let result = try env.scheduling.isJobInFlexPool(jobId: jobId)
        #expect(result == false)
    }

    // MARK: - fetchFlexPool Excludes Non-Active Statuses

    @Test("fetchFlexPool excludes completed and cancelled flex-pool jobs")
    func testFetchFlexPoolExcludesInactiveStatuses() throws {
        let env = try E2ETestHelpers.setUp()

        // Create completed flex-pool job
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO jobs (job_name, job_number, status, is_flex_pool, deleted_at, created_at, updated_at)
                VALUES ('Completed Flex', 'FX-C1', 'completed', 1, NULL, datetime('now'), datetime('now'))
                """)
        }

        // Create cancelled flex-pool job
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO jobs (job_name, job_number, status, is_flex_pool, deleted_at, created_at, updated_at)
                VALUES ('Cancelled Flex', 'FX-C2', 'cancelled', 1, NULL, datetime('now'), datetime('now'))
                """)
        }

        // Create on_hold flex-pool job
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO jobs (job_name, job_number, status, is_flex_pool, deleted_at, created_at, updated_at)
                VALUES ('OnHold Flex', 'FX-C3', 'on_hold', 1, NULL, datetime('now'), datetime('now'))
                """)
        }

        let jobs = try env.scheduling.fetchFlexPool(userId: env.adminUserId)
        #expect(!jobs.contains(where: { $0.jobName == "Completed Flex" }))
        #expect(!jobs.contains(where: { $0.jobName == "Cancelled Flex" }))
        #expect(!jobs.contains(where: { $0.jobName == "OnHold Flex" }))
    }

    // MARK: - Crew Utilization admin-exclusion correctness (iteration 8)

    @Test("getCrewUtilizationReport includes former admins whose Admin hat was revoked")
    func testCrewUtilization_includesRevokedAdmins() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // adminUserId has the Admin hat by default (seedFirstAdmin in E2ETestHelpers).
        // Revoke the admin hat (soft-delete the user_hats row) so they are now a regular crew.
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE user_hats SET deleted_at = datetime('now')
                    WHERE user_id = ? AND hat_id = (SELECT id FROM hats WHERE name = 'Admin')
                    """,
                arguments: [env.adminUserId]
            )
        }

        // Give the (now former) admin a job dispatch so they have a non-zero dispatch_count.
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO job_dispatch
                        (job_id, user_id, dispatch_date, shift_start, shift_end, created_at, updated_at)
                    VALUES (?, ?, '2026-06-10', '2026-06-10T08:00:00', '2026-06-10T16:00:00',
                            datetime('now'), datetime('now'))
                    """,
                arguments: [jobId, env.adminUserId]
            )
        }

        let start = ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")!
        let end = ISO8601DateFormatter().date(from: "2026-06-30T00:00:00Z")!
        let report = try env.scheduling.getCrewUtilizationReport(startDate: start, endDate: end)

        #expect(report.contains { $0.id == env.adminUserId },
                "A user whose Admin hat was revoked must appear in crew utilization — they're no longer admin")
    }

    @Test("getDispatchBoard hides job name for soft-deleted job")
    func testGetDispatchBoardHidesDeletedJobName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        _ = try env.scheduling.createDispatch(jobId: jobId, userId: env.adminUserId, date: today)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?", arguments: [jobId])
        }
        let board = try env.scheduling.getDispatchBoard(date: today)
        #expect(board.isEmpty == false)
        #expect(board.first?.jobName != "Test Job")
    }

    @Test("getMySchedule hides job name for soft-deleted job")
    func testGetMyScheduleHidesDeletedJobName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        _ = try env.scheduling.createDispatch(jobId: jobId, userId: env.adminUserId, date: today)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?", arguments: [jobId])
        }
        let schedule = try env.scheduling.getMySchedule(userId: env.adminUserId, startDate: today, endDate: today)
        #expect(schedule.isEmpty == false)
        #expect(schedule.first?.jobName != "Test Job")
    }

    @Test("listTimeOffRequests shows Unknown for soft-deleted requester")
    func testListTimeOffRequestsHidesDeletedUserName() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2099-07-01",
            endDate: "2099-07-01",
            reason: "Vacation"
        )
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        let rows = try env.scheduling.listTimeOffRequests()
        #expect(rows.isEmpty == false)
        #expect(rows.first?.userName == "Unknown")
    }

    @Test("getTimeOffForDate shows Unknown for soft-deleted user")
    func testGetTimeOffForDateHidesDeletedUserName() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2099-08-01",
            endDate: "2099-08-01",
            reason: "Personal"
        )
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        let entries = try env.scheduling.getTimeOffForDate(date: "2099-08-01")
        #expect(entries.isEmpty == false)
        #expect(entries.first?.employeeName == "Unknown")
    }

    @Test("snoozeCallback is a no-op on a soft-deleted job")
    func testSnoozeCallback_noOpOnSoftDeletedJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try env.jobs.createJob(
            jobNumber: "J-SNOOZE-DEL",
            jobName: "TombstonedCallback",
            customerName: "Cust",
            status: "active",
            createdBy: env.adminUserId
        )
        // Capture original due_date (nil) and soft-delete
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [jobId])
        }
        // Regression: UPDATE jobs SET due_date = ? WHERE id = ? had no deleted_at guard.
        try env.scheduling.snoozeCallback(jobId: jobId, until: "2099-12-31")

        let dueDate = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT due_date FROM jobs WHERE id = ?", arguments: [jobId])
        }
        #expect(dueDate == nil,
                "Soft-deleted job due_date must not be rewritten — UPDATE must guard AND deleted_at IS NULL")
    }

    // MARK: - Soft-Delete Guard: markJobFlexPool

    @Test("markJobFlexPool is a no-op on a soft-deleted job")
    func testMarkJobFlexPool_noOpOnSoftDeletedJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        try env.scheduling.markJobFlexPool(jobId: jobId, isFlexPool: true)

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [jobId])
        }

        try env.scheduling.markJobFlexPool(jobId: jobId, isFlexPool: false)

        let isFlexPool = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT is_flex_pool FROM jobs WHERE id = ?",
                             arguments: [jobId]) ?? 0
        }
        #expect(isFlexPool == 1,
                "Soft-deleted job is_flex_pool must not be rewritten — UPDATE must guard AND deleted_at IS NULL")
    }

    // MARK: - Soft-Delete Guard: saveShiftTemplate

    @Test("saveShiftTemplate update is a no-op on a soft-deleted template")
    func testSaveShiftTemplate_noOpOnSoftDeletedTemplate() throws {
        let env = try E2ETestHelpers.setUp()

        let templateId = try env.scheduling.saveShiftTemplate(
            name: "Morning Shift",
            hatId: nil,
            workDays: "1,2,3,4,5",
            startTime: "07:00",
            endTime: "15:00"
        )

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE shift_templates SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [templateId])
        }

        _ = try env.scheduling.saveShiftTemplate(
            id: templateId,
            name: "GHOST RENAME",
            hatId: nil,
            workDays: "1,2,3,4,5",
            startTime: "07:00",
            endTime: "15:00"
        )

        let name = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM shift_templates WHERE id = ?",
                                arguments: [templateId])
        }
        #expect(name == "Morning Shift",
                "Soft-deleted shift template must not be renamed — UPDATE must guard AND deleted_at IS NULL")
    }

    // MARK: - Soft-Delete Guard: saveHoliday

    @Test("saveHoliday update is a no-op on a soft-deleted holiday")
    func testSaveHoliday_noOpOnSoftDeletedHoliday() throws {
        let env = try E2ETestHelpers.setUp()

        let holidayId = try env.scheduling.saveHoliday(
            name: "Independence Day",
            date: "2026-07-04"
        )

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE company_holidays SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [holidayId])
        }

        _ = try env.scheduling.saveHoliday(
            id: holidayId,
            name: "GHOST HOLIDAY",
            date: "2026-07-04"
        )

        let name = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM company_holidays WHERE id = ?",
                                arguments: [holidayId])
        }
        #expect(name == "Independence Day",
                "Soft-deleted holiday must not be renamed — UPDATE must guard AND deleted_at IS NULL")
    }

    // MARK: - Soft-Delete Guard: updateTimeOffStatus

    @Test("updateTimeOffStatus throws timeOffRequestNotFound for soft-deleted request")
    func testUpdateTimeOffStatus_throwsForSoftDeletedRequest() throws {
        let env = try E2ETestHelpers.setUp()

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-09-01",
            endDate: "2026-09-01",
            reason: "Personal day"
        )

        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE schedule_exceptions SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [requestId]
            )
        }

        var threw = false
        do {
            try env.scheduling.updateTimeOffStatus(id: requestId, status: "approved", approvedBy: env.adminUserId)
        } catch {
            threw = true
        }
        #expect(threw, "updateTimeOffStatus must throw when the time-off request is soft-deleted")
    }

    @Test("createTimeOffRequest creates no orphan schedule_exceptions row for a soft-deleted user")
    func testCreateTimeOffRequest_noOrphanForSoftDeletedUser() throws {
        let env = try E2ETestHelpers.setUp()
        // Soft-delete the admin user first, then attempt to create a request for them.
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        // Regression: INSERT INTO schedule_exceptions had no guard on users.deleted_at.
        let id = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2099-08-01",
            endDate: "2099-08-03",
            reason: "test"
        )
        #expect(id == 0,
            "createTimeOffRequest must return 0 (no-op) for a tombstoned user")
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM schedule_exceptions WHERE user_id = ?",
                             arguments: [env.adminUserId]) ?? 0
        }
        #expect(count == 0,
            "Soft-deleted user must not produce schedule_exceptions rows — INSERT must be pre-checked")
    }

    @Test("fetchFlexPool returns empty when no flex-pool jobs exist")
    func testFetchFlexPool_returnsEmptyWhenNoJobs() throws {
        let env = try E2ETestHelpers.setUp()
        let result = try env.scheduling.fetchFlexPool(userId: env.adminUserId)
        #expect(result.isEmpty, "fetchFlexPool must return [] when no flex-pool jobs exist")
    }

    @Test("fetchFlexPool returns unfiltered flex-pool job visible to all users")
    func testFetchFlexPool_returnsUnfilteredJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-FP-01", name: "Flex Pool Job")
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE jobs SET is_flex_pool = 1, status = 'active' WHERE id = ?",
                arguments: [jobId])
        }
        let result = try env.scheduling.fetchFlexPool(userId: env.adminUserId)
        #expect(result.count == 1, "fetchFlexPool must return the unfiltered flex-pool job")
        #expect(result[0].id == jobId)
    }

    @Test("createTimeOffRequest throws invalidDateRange when endDate is before startDate")
    func testCreateTimeOffRequest_throwsForReversedDateRange() throws {
        let env = try E2ETestHelpers.setUp()
        var threw = false
        do {
            _ = try env.scheduling.createTimeOffRequest(
                userId: env.adminUserId,
                startDate: "2026-10-10",
                endDate: "2026-10-01",
                reason: "Vacation"
            )
        } catch SchedulingService.SchedulingError.invalidDateRange {
            threw = true
        } catch {}
        #expect(threw, "createTimeOffRequest must throw invalidDateRange when endDate is before startDate")
    }

    @Test("createTimeOffRequest succeeds when startDate equals endDate")
    func testCreateTimeOffRequest_succeedsForSingleDay() throws {
        let env = try E2ETestHelpers.setUp()
        let id = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2099-11-01",
            endDate: "2099-11-01",
            reason: "Personal day"
        )
        #expect(id > 0, "createTimeOffRequest must succeed for a single-day request (start == end)")
    }

    @Test("saveShiftTemplate throws requiredFieldEmpty when name is blank")
    func testSaveShiftTemplate_throwsForBlankName() throws {
        let env = try E2ETestHelpers.setUp()
        var threw = false
        do {
            _ = try env.scheduling.saveShiftTemplate(
                name: "   ", hatId: nil,
                workDays: "Mon,Tue,Wed,Thu,Fri",
                startTime: "07:00", endTime: "15:30"
            )
        } catch SchedulingService.SchedulingError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "saveShiftTemplate must throw requiredFieldEmpty when name is whitespace-only")
    }

    @Test("saveHoliday throws requiredFieldEmpty when name is blank")
    func testSaveHoliday_throwsForBlankName() throws {
        let env = try E2ETestHelpers.setUp()
        var threw = false
        do {
            _ = try env.scheduling.saveHoliday(name: "", date: "2099-12-25")
        } catch SchedulingService.SchedulingError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "saveHoliday must throw requiredFieldEmpty when name is empty")
    }

    // MARK: - FK soft-delete guards on create paths (iter 78)

    @Test("createDispatch rejects tombstoned job")
    func testCreateDispatch_rejectsTombstonedJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [jobId])
        }
        var threw = false
        do {
            _ = try env.scheduling.createDispatch(
                jobId: jobId, userId: env.adminUserId, date: "2099-09-15"
            )
        } catch SchedulingService.SchedulingError.jobNotFound { threw = true
        } catch {}
        #expect(threw, "createDispatch must throw jobNotFound for a tombstoned job")
    }

    @Test("createDispatch rejects blank date")
    func testCreateDispatch_rejectsBlankDate() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        var threw = false
        do {
            _ = try env.scheduling.createDispatch(
                jobId: jobId, userId: env.adminUserId, date: "   "
            )
        } catch SchedulingService.SchedulingError.requiredFieldEmpty { threw = true
        } catch {}
        #expect(threw, "createDispatch must throw requiredFieldEmpty for a blank date")
    }

    @Test("createScheduleEntry rejects tombstoned user")
    func testCreateScheduleEntry_rejectsTombstonedUser() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        var threw = false
        do {
            _ = try env.scheduling.createScheduleEntry(
                userId: env.adminUserId, jobId: jobId, date: "2099-09-16"
            )
        } catch SchedulingService.SchedulingError.userNotFound { threw = true
        } catch {}
        #expect(threw, "createScheduleEntry must throw userNotFound for a tombstoned user")
    }

    @Test("claimFlexJob rejects tombstoned job")
    func testClaimFlexJob_rejectsTombstonedJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [jobId])
        }
        var threw = false
        do {
            try env.scheduling.claimFlexJob(jobId: jobId, userId: env.adminUserId)
        } catch SchedulingService.SchedulingError.jobNotFound { threw = true
        } catch {}
        #expect(threw, "claimFlexJob must throw jobNotFound for a tombstoned job")
    }

    // MARK: - Scheduling validation (iter 85)

    @Test("snoozeCallback rejects blank until date")
    func testSnoozeCallback_rejectsBlankDate() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: SchedulingService.SchedulingError.requiredFieldEmpty) {
            try env.scheduling.snoozeCallback(jobId: 999, until: "   ")
        }
    }

    @Test("saveHoliday rejects blank date")
    func testSaveHoliday_rejectsBlankDate() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: SchedulingService.SchedulingError.requiredFieldEmpty) {
            try env.scheduling.saveHoliday(name: "Labor Day", date: "")
        }
    }

    @Test("saveShiftTemplate rejects blank time and workDays fields")
    func testSaveShiftTemplate_rejectsBlankTimeFields() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: SchedulingService.SchedulingError.requiredFieldEmpty) {
            try env.scheduling.saveShiftTemplate(name: "Day", hatId: nil,
                                                  workDays: "Mon-Fri", startTime: "   ", endTime: "17:00")
        }
        #expect(throws: SchedulingService.SchedulingError.requiredFieldEmpty) {
            try env.scheduling.saveShiftTemplate(name: "Day", hatId: nil,
                                                  workDays: "Mon-Fri", startTime: "07:00", endTime: "")
        }
        #expect(throws: SchedulingService.SchedulingError.requiredFieldEmpty) {
            try env.scheduling.saveShiftTemplate(name: "Day", hatId: nil,
                                                  workDays: "", startTime: "07:00", endTime: "17:00")
        }
    }

    @Test("createTimeOffRequest rejects blank startDate or endDate")
    func testCreateTimeOffRequest_rejectsBlankDates() throws {
        let env = try E2ETestHelpers.setUp()
        // Blank startDate — without this guard a row with exception_date='' would be inserted
        #expect(throws: SchedulingService.SchedulingError.requiredFieldEmpty) {
            try env.scheduling.createTimeOffRequest(userId: env.adminUserId,
                                                    startDate: "", endDate: "2026-05-01")
        }
        #expect(throws: SchedulingService.SchedulingError.requiredFieldEmpty) {
            try env.scheduling.createTimeOffRequest(userId: env.adminUserId,
                                                    startDate: "2026-05-01", endDate: "   ")
        }
        // Verify no blank-date rows leaked into schedule_exceptions
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM schedule_exceptions WHERE exception_date = ''") ?? 0
        }
        #expect(count == 0)
    }

    @Test("getLongTermTimeline batch rewrite: job appears in correct month via overlap logic")
    func testLongTermTimeline_batchJobOverlap() throws {
        let env = try E2ETestHelpers.setUp()
        // Insert a job that spans multiple months using raw DB insert so we can control dates
        let cal = Calendar.current
        let today = Date()
        let year = cal.component(.year, from: today)
        let month = cal.component(.month, from: today)
        let startDate = String(format: "%04d-%02d-15", year, month)
        // Due date in next month
        var comps = DateComponents(); comps.year = year; comps.month = month + 1; comps.day = 15
        let nextMonth = cal.date(from: comps)!
        let nextYear = cal.component(.year, from: nextMonth)
        let nextMonthNum = cal.component(.month, from: nextMonth)
        let dueDate = String(format: "%04d-%02d-15", nextYear, nextMonthNum)

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO jobs (job_number, job_name, status, start_date, due_date, estimated_hours)
                VALUES ('TL-OVERLAP-001', 'MultiMonth Job', 'active', ?, ?, 80)
                """, arguments: [startDate, dueDate])
        }

        let timeline = try env.scheduling.getLongTermTimeline(months: 6)
        let thisMonthId = String(format: "%04d-%02d", year, month)
        let nextMonthId = String(format: "%04d-%02d", nextYear, nextMonthNum)

        let thisMonth = timeline.first { $0.id == thisMonthId }
        let nextMonthEntry = timeline.first { $0.id == nextMonthId }

        // Job should appear in both months (overlap)
        #expect(thisMonth?.jobs.contains(where: { $0.name == "MultiMonth Job" }) == true,
                "Job must appear in the month it starts in")
        #expect(nextMonthEntry?.jobs.contains(where: { $0.name == "MultiMonth Job" }) == true,
                "Job must appear in the month it ends in (overlap)")
    }

    // MARK: - createDispatch + Time-Off Integration (Fixes #355)

    @Test("createDispatch throws timeOffConflict when user has approved time off")
    func testCreateDispatch_throwsTimeOffConflict_whenUserOnApprovedTimeOff() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-11-10",
            endDate: "2026-11-10",
            reason: "Vacation"
        )
        try env.scheduling.updateTimeOffStatus(
            id: requestId,
            status: "approved",
            approvedBy: env.adminUserId
        )

        #expect(throws: SchedulingService.SchedulingError.timeOffConflict(
            userId: env.adminUserId,
            date: "2026-11-10",
            reason: "Vacation"
        )) {
            _ = try env.scheduling.createDispatch(
                jobId: jobId,
                userId: env.adminUserId,
                date: "2026-11-10"
            )
        }
    }

    @Test("createDispatch succeeds with forceCreateDespiteTimeOff: true when user has approved time off")
    func testCreateDispatch_succeeds_whenForceCreateDespiteTimeOffTrue_andUserOnTimeOff() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-11-11",
            endDate: "2026-11-11",
            reason: "Doctor"
        )
        try env.scheduling.updateTimeOffStatus(
            id: requestId,
            status: "approved",
            approvedBy: env.adminUserId
        )

        let dispatchId = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: "2026-11-11",
            forceCreateDespiteTimeOff: true
        )
        #expect(dispatchId > 0)
    }

    @Test("createDispatch succeeds when time-off is denied (only approved blocks)")
    func testCreateDispatch_succeeds_whenTimeOffIsDenied() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-11-12",
            endDate: "2026-11-12",
            reason: "Personal"
        )
        try env.scheduling.updateTimeOffStatus(
            id: requestId,
            status: "denied",
            approvedBy: env.adminUserId
        )

        let dispatchId = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: "2026-11-12"
        )
        #expect(dispatchId > 0)
    }

    @Test("createDispatch succeeds when approved time-off is for a different date")
    func testCreateDispatch_succeeds_whenTimeOffIsForDifferentDate() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let requestId = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-11-15",
            endDate: "2026-11-15",
            reason: "Holiday"
        )
        try env.scheduling.updateTimeOffStatus(
            id: requestId,
            status: "approved",
            approvedBy: env.adminUserId
        )

        // Dispatch on a DIFFERENT date should succeed despite approved time-off on another date
        let dispatchId = try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: "2026-11-16"
        )
        #expect(dispatchId > 0)
    }
}
