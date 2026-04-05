import Testing
import Foundation
@testable import WiredPartCore

/// Tests for BadgeCountService — verifies that all SQL queries use the correct
/// column/table names from the actual schema and return correct counts.
@Suite("BadgeCountService Tests")
struct BadgeCountServiceTests {

    // MARK: - Baseline: fresh DB returns all zeros

    @Test("getAllBadgeCounts returns all zeros on fresh database")
    func testFreshDatabaseReturnsAllZeros() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)
        let counts = try service.getAllBadgeCounts(userId: env.adminUserId)
        #expect(counts.pendingApprovals == 0)
        #expect(counts.activeClockedIn == 0)
        #expect(counts.openDispatches == 0)
        #expect(counts.pendingReceipts == 0)
        #expect(counts.overdueOrders == 0)
        #expect(counts.expiringCerts == 0)
        #expect(counts.pendingTimeOff == 0)
        #expect(counts.pendingDeletions == 0)
        #expect(counts.unreadMessages == 0)
        #expect(counts.unreadNotebookEntries == 0)
        #expect(counts.oldestPendingDate == nil)
    }

    // MARK: - pendingApprovals: JPO with status='submitted'

    @Test("pendingApprovals counts submitted JPOs")
    func testPendingApprovalsCountsSubmittedJPOs() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        let jobId = try env.jobs.createJob(
            jobNumber: "J-BADGE-001",
            jobName: "Badge Test Job",
            customerName: "Test Customer",
            status: "active",
            createdBy: env.adminUserId
        )
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        try env.orders.updateJPOStatus(id: jpoId, status: "submitted")

        let counts = try service.getAllBadgeCounts()
        #expect(counts.pendingApprovals == 1)
    }

    // MARK: - pendingTimeOff: schedule_exceptions (not pto_transactions)

    @Test("pendingTimeOff counts unapproved time-off via schedule_exceptions (not pto_transactions)")
    func testPendingTimeOffUsesScheduleExceptions() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        // Zero before any request
        let before = try service.getAllBadgeCounts()
        #expect(before.pendingTimeOff == 0)

        // Create a single-day time-off request
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let dateStr = ISO8601DateFormatter().string(from: tomorrow).prefix(10).description
        try env.scheduling.createTimeOffRequest(
            userId: env.adminUserId,
            startDate: dateStr,
            endDate: dateStr,
            reason: "Test vacation"
        )

        // Pending count should now be 1 (grouped by request_group)
        let after = try service.getAllBadgeCounts()
        #expect(after.pendingTimeOff == 1)
    }

    // MARK: - pendingDeletions: scheduled_deletions with status='pending_approval'

    @Test("pendingDeletions uses 'pending_approval' (not 'pending') and counts correctly")
    func testPendingDeletionsUsesPendingApprovalStatus() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        // Zero before any scheduled deletion
        let before = try service.getAllBadgeCounts()
        #expect(before.pendingDeletions == 0)

        // An entity with no stock gets status='pending_approval' immediately
        // (service logic: currentStock == 0 → 'pending_approval', else 'draining')
        let catId = try env.parts.createCategory(name: "ToDelete")
        try env.parts.scheduleEmptyShelfDeletion(
            entityType: "category",
            entityId: catId,
            entityName: "ToDelete",
            reason: nil,
            scheduledBy: env.adminUserId
        )

        // Should count 1 — confirms the query uses 'pending_approval' not the incorrect 'pending'
        let after = try service.getAllBadgeCounts()
        #expect(after.pendingDeletions == 1,
            "Empty entity should immediately have status='pending_approval' and be counted")
    }

    // MARK: - openDispatches: job_dispatch uses user_id (not the old worker_id)

    @Test("openDispatches counts dispatched jobs for today using job_dispatch.user_id")
    func testOpenDispatchesUsesCorrectColumnName() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        let before = try service.getAllBadgeCounts()
        #expect(before.openDispatches == 0)

        let jobId = try env.jobs.createJob(
            jobNumber: "J-BADGE-002",
            jobName: "Dispatch Test Job",
            customerName: "Test Customer",
            status: "active",
            createdBy: env.adminUserId
        )
        let todayStr = ISO8601DateFormatter().string(from: Date()).prefix(10).description
        try env.scheduling.createDispatch(
            jobId: jobId,
            userId: env.adminUserId,
            date: todayStr
        )

        // Should count 1 distinct job dispatched today with status='scheduled'
        let after = try service.getAllBadgeCounts()
        #expect(after.openDispatches == 1)
    }

    // MARK: - Per-tab badge aggregates

    @Test("officeBadge aggregates pendingApprovals + pendingTimeOff + pendingToolEdits + pendingDeletions")
    func testOfficeBadgeAggregation() {
        let counts = BadgeCountService.BadgeCounts(
            pendingApprovals: 3,
            pendingTimeOff: 2,
            pendingToolEdits: 1,
            pendingDeletions: 4
        )
        #expect(counts.officeBadge == 10)
    }

    @Test("ordersBadge aggregates pendingApprovals + overdueOrders")
    func testOrdersBadgeAggregation() {
        let counts = BadgeCountService.BadgeCounts(
            pendingApprovals: 2,
            overdueOrders: 5
        )
        #expect(counts.ordersBadge == 7)
    }

    @Test("badge(for:) routes correctly for all module IDs")
    func testBadgeForModuleId() {
        let counts = BadgeCountService.BadgeCounts(
            pendingApprovals: 3,
            activeClockedIn: 2,
            openDispatches: 1,
            pendingReceipts: 4,
            expiringCerts: 5,
            unreadNotebookEntries: 6
        )
        #expect(counts.badge(for: "dashboard") == 2)
        #expect(counts.badge(for: "scheduling") == 1)
        #expect(counts.badge(for: "warehouse") == 4)
        #expect(counts.badge(for: "people") == 5)
        #expect(counts.badge(for: "notebooks") == 6)
        #expect(counts.badge(for: "unknown") == 0)
    }

    // MARK: - hasOldItems threshold

    @Test("hasOldItems returns false when oldest pending date is within 7 days")
    func testHasOldItemsFalseForRecentDate() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let counts = BadgeCountService.BadgeCounts(oldestPendingDate: formatter.string(from: yesterday))
        #expect(counts.hasOldItems == false)
    }

    @Test("hasOldItems returns true when oldest pending date exceeds 7 days")
    func testHasOldItemsTrueForOldDate() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let counts = BadgeCountService.BadgeCounts(oldestPendingDate: formatter.string(from: tenDaysAgo))
        #expect(counts.hasOldItems == true)
    }

    // MARK: - activeClockedIn: labor_entries with no clock_out

    @Test("activeClockedIn counts workers currently clocked in")
    func testActiveClockedIn() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        let before = try service.getAllBadgeCounts()
        #expect(before.activeClockedIn == 0)

        let jobId = try env.jobs.createJob(
            jobNumber: "J-BADGE-CLK",
            jobName: "Clock Test Job",
            customerName: "Test Customer",
            status: "active",
            createdBy: env.adminUserId
        )
        _ = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)

        let after = try service.getAllBadgeCounts()
        #expect(after.activeClockedIn == 1)
    }

    // MARK: - Individual count methods

    @Test("pendingApprovalCount() matches getAllBadgeCounts.pendingApprovals")
    func testPendingApprovalCountIndividual() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        // Zero on fresh DB
        #expect(try service.pendingApprovalCount() == 0)

        let jobId = try env.jobs.createJob(
            jobNumber: "J-BADGE-IND",
            jobName: "Individual Count Job",
            customerName: "Test Customer",
            status: "active",
            createdBy: env.adminUserId
        )
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        try env.orders.updateJPOStatus(id: jpoId, status: "submitted")

        #expect(try service.pendingApprovalCount() == 1)
    }

    @Test("pendingReceiptCount() counts active receiving sessions")
    func testPendingReceiptCountIndividual() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        #expect(try service.pendingReceiptCount() == 0)

        // Insert a PO, then start a receiving session against it
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO purchase_orders (po_number, supplier_id, status)
                VALUES ('PO-RCPT-001', ?, 'ordered')
                """, arguments: [supplierId])
        }
        let poId = try env.db.writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM purchase_orders WHERE po_number = 'PO-RCPT-001'")!
        }
        _ = try env.warehouse.startReceivingSession(poId: poId, startedBy: env.adminUserId)

        #expect(try service.pendingReceiptCount() == 1)
    }

    @Test("overdueOrderCount() counts POs with past expected_delivery")
    func testOverdueOrderCountIndividual() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        #expect(try service.overdueOrderCount() == 0)

        // Insert a PO directly with an overdue expected_delivery
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO purchase_orders
                    (po_number, supplier_id, status, expected_delivery)
                VALUES ('PO-OVERDUE-001', ?, 'ordered', date('now', '-1 day'))
                """, arguments: [supplierId])
        }

        #expect(try service.overdueOrderCount() == 1)
    }

    @Test("expiringCertCount(withinDays:) counts certs expiring within window")
    func testExpiringCertCountIndividual() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        #expect(try service.expiringCertCount(withinDays: 7) == 0)

        // Insert a cert expiring in 3 days (within 7-day window)
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO certifications
                    (user_id, cert_type, cert_name, expiry_date, is_active)
                VALUES (?, 'safety', 'OSHA 10', date('now', '+3 days'), 1)
                """, arguments: [env.adminUserId])
        }

        #expect(try service.expiringCertCount(withinDays: 7) == 1)
        // A cert expiring in 3 days is NOT within a 2-day window
        #expect(try service.expiringCertCount(withinDays: 2) == 0)
    }
}
