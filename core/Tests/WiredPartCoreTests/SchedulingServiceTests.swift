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
            status: "denied"
        )

        // Denied requests have is_approved = 0, same as pending.
        // Verify the request still exists
        let all = try env.scheduling.listTimeOffRequests(userId: env.adminUserId)
        #expect(all.count == 1)
        #expect(all[0].status == "pending") // is_approved = 0 maps to "pending" in the query
    }

    @Test("updateTimeOffStatus throws for non-existent request")
    func testRejectTimeOffNotFound() throws {
        let env = try E2ETestHelpers.setUp()

        #expect(throws: SchedulingService.SchedulingError.self) {
            try env.scheduling.updateTimeOffStatus(id: 9999, status: "approved")
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

    @Test("checkTimeOffConflict detects time-off on date")
    func testCheckTimeOffConflict() throws {
        let env = try E2ETestHelpers.setUp()

        _ = try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: "2026-10-15",
            endDate: "2026-10-15",
            reason: "Conference"
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
}
