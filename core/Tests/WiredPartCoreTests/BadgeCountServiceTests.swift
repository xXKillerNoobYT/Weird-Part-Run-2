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

    @Test("pendingApprovals counts pending/in-review JPOs")
    func testPendingApprovalsCountsPendingJPOs() throws {
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
        // "draft" → "pending" is the valid transition for submitting a JPO for approval
        try env.orders.updateJPOStatus(id: jpoId, status: "pending")

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
        // "draft" → "pending" is the valid transition for submitting a JPO for approval
        try env.orders.updateJPOStatus(id: jpoId, status: "pending")

        #expect(try service.pendingApprovalCount() == 1)
    }

    @Test("pendingApprovals also counts in_review JPOs (both states need approver action)")
    func testPendingApprovalsCountsInReviewJPOs() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        let jobId = try env.jobs.createJob(
            jobNumber: "J-BADGE-INR",
            jobName: "In-Review Badge Test",
            customerName: "Test Customer",
            status: "active",
            createdBy: env.adminUserId
        )
        // Advance: draft → pending → in_review (both valid transitions)
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        try env.orders.updateJPOStatus(id: jpoId, status: "pending")
        try env.orders.updateJPOStatus(id: jpoId, status: "in_review")

        let counts = try service.getAllBadgeCounts()
        // An in_review JPO still requires approver action — must appear in pendingApprovals
        #expect(counts.pendingApprovals == 1)
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

    @Test("unreadMessages excludes channels where user is not an active member")
    func testUnreadMessagesRequiresActiveChannelMembership() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        let senderId = try env.auth.createUser(displayName: "Other Sender", pin: "1357", email: "badge-sender@test.com")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO chat_channels (channel_type, name, created_by, is_active)
                VALUES ('group', 'Private Badge Channel', ?, 1)
                """, arguments: [senderId])
            let channelId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO chat_channel_members (channel_id, user_id, role, joined_at)
                VALUES (?, ?, 'member', datetime('now'))
                """, arguments: [channelId, senderId])
            try db.execute(sql: """
                INSERT INTO chat_messages (channel_id, sender_id, message_type, content, created_at)
                VALUES (?, ?, 'text', 'private message', datetime('now'))
                """, arguments: [channelId, senderId])
        }

        let counts = try service.getAllBadgeCounts(userId: env.adminUserId)
        #expect(counts.unreadMessages == 0,
            "Unread chat badge must only count messages in channels where the user has an active membership")
    }

    @Test("unreadMessages excludes channels whose membership was removed")
    func testUnreadMessagesRequiresNonRemovedMembership() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        let senderId = try env.auth.createUser(displayName: "Removal Sender", pin: "2468", email: "badge-removal-sender@test.com")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO chat_channels (channel_type, name, created_by, is_active)
                VALUES ('group', 'Removed Badge Channel', ?, 1)
                """, arguments: [senderId])
            let channelId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO chat_channel_members (channel_id, user_id, role, joined_at)
                VALUES (?, ?, 'member', datetime('now'))
                """, arguments: [channelId, senderId])
            try db.execute(sql: """
                INSERT INTO chat_channel_members (channel_id, user_id, role, joined_at, left_at)
                VALUES (?, ?, 'member', datetime('now'), datetime('now'))
                """, arguments: [channelId, env.adminUserId])
            try db.execute(sql: """
                INSERT INTO chat_messages (channel_id, sender_id, message_type, content, created_at)
                VALUES (?, ?, 'text', 'removed membership private message', datetime('now'))
                """, arguments: [channelId, senderId])
        }

        let counts = try service.getAllBadgeCounts(userId: env.adminUserId)
        #expect(counts.unreadMessages == 0,
            "Unread chat badge must not count channels with left_at/deleted_at memberships")
    }

    @Test("unreadNotebookEntries excludes job notebooks whose team membership was soft-deleted")
    func testUnreadNotebookEntries_ignoresSoftDeletedTeamMembership() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        let jobId = try env.jobs.createJob(
            jobNumber: "J-BADGE-TM",
            jobName: "Tombstoned Team Member Job",
            customerName: "Test Customer",
            status: "active",
            createdBy: env.adminUserId
        )

        // Tombstone the admin's team membership on this job. The JOIN-via-jtm on
        // BadgeCountService line 211 previously had no `jtm.deleted_at IS NULL` guard,
        // so a removed team member would keep seeing unread counts for the job's notebooks.
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO job_team_members (job_id, user_id, role, deleted_at)
                VALUES (?, ?, 'member', datetime('now'))
                """, arguments: [jobId, env.adminUserId])
        }

        // Create a job-scoped notebook + section + recently-updated entry
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO notebooks (title, notebook_type, job_id, created_by)
                VALUES ('Team-Only Book', 'job', ?, ?)
                """, arguments: [jobId, env.adminUserId])
            let nbId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO notebook_sections (notebook_id, name, sort_order)
                VALUES (?, 'Main', 0)
                """, arguments: [nbId])
            let secId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO notebook_entries
                    (notebook_id, section_id, title, content, entry_type, created_by, updated_at)
                VALUES (?, ?, 'Entry', 'body', 'note', ?, datetime('now'))
                """, arguments: [nbId, secId, env.adminUserId])
        }

        let counts = try service.getAllBadgeCounts(userId: env.adminUserId)
        #expect(counts.unreadNotebookEntries == 0,
            "Soft-deleted team membership must not grant visibility — JOIN must guard jtm.deleted_at IS NULL")
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

    // MARK: - oldestPendingDate considers every badge queue (#708)
    //
    // The age/tint signal previously only scanned pending/in-review JPOs, so
    // stale time-off, tool-edit, and deletion approvals were counted in the
    // Office badge number but invisible to hasOldItems.

    @Test("oldest pending time-off with no pending JPO drives hasOldItems")
    func testOldestPendingDateIncludesStaleTimeOff() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        // A 10-day-old unapproved time-off request; no JPOs exist at all.
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO schedule_exceptions
                    (user_id, exception_date, exception_type, is_approved, created_at)
                VALUES (?, date('now', '+1 day'), 'time_off', 0, datetime('now', '-10 days'))
                """, arguments: [env.adminUserId])
        }

        let counts = try service.getAllBadgeCounts(userId: env.adminUserId)
        #expect(counts.pendingApprovals == 0)
        #expect(counts.pendingTimeOff == 1)
        #expect(counts.oldestPendingDate != nil,
            "Stale time-off approvals must feed the badge age signal, not just the count")
        #expect(counts.hasOldItems == true,
            "A 10-day-old pending time-off request must trigger the aged badge tint")
    }

    @Test("oldest pending tool edit verification with no pending JPO drives hasOldItems")
    func testOldestPendingDateIncludesStaleToolEdits() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        // A tool with a 10-day-old pending edit verification; no JPOs exist.
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO tools (tool_number, name) VALUES ('T-708', 'Badge Age Drill')
                """)
            let toolId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO tool_change_log
                    (tool_id, changed_by, change_type, verification_status, changed_at)
                VALUES (?, ?, 'edit', 'pending', datetime('now', '-10 days'))
                """, arguments: [toolId, env.adminUserId])
        }

        let counts = try service.getAllBadgeCounts(userId: env.adminUserId)
        #expect(counts.pendingApprovals == 0)
        #expect(counts.pendingToolEdits == 1)
        #expect(counts.oldestPendingDate != nil,
            "Stale tool edit verifications must feed the badge age signal")
        #expect(counts.hasOldItems == true,
            "A 10-day-old pending tool edit must trigger the aged badge tint")
    }

    @Test("oldest pending deletion approval with no pending JPO drives hasOldItems")
    func testOldestPendingDateIncludesStaleDeletions() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        // A 10-day-old deletion awaiting approval; no JPOs exist.
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO scheduled_deletions
                    (entity_type, entity_id, entity_name, status, created_at)
                VALUES ('category', 999, 'Stale Deletion', 'pending_approval', datetime('now', '-10 days'))
                """)
        }

        let counts = try service.getAllBadgeCounts(userId: env.adminUserId)
        #expect(counts.pendingApprovals == 0)
        #expect(counts.pendingDeletions == 1)
        #expect(counts.oldestPendingDate != nil,
            "Stale deletion approvals must feed the badge age signal")
        #expect(counts.hasOldItems == true,
            "A 10-day-old pending deletion approval must trigger the aged badge tint")
    }

    @Test("pending JPOs still feed oldestPendingDate, and the overall oldest queue wins")
    func testOldestPendingDatePicksOverallOldestAcrossQueues() throws {
        let env = try E2ETestHelpers.setUp()
        let service = BadgeCountService(db: env.db)

        // Recent pending JPO (3 days old) — within the 7-day threshold on its own.
        let jobId = try env.jobs.createJob(
            jobNumber: "J-BADGE-708",
            jobName: "Oldest Queue Job",
            customerName: "Test Customer",
            status: "active",
            createdBy: env.adminUserId
        )
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        try env.orders.updateJPOStatus(id: jpoId, status: "pending")
        try env.db.writer.write { db in
            try db.execute(sql: """
                UPDATE job_parts_orders SET created_at = datetime('now', '-3 days') WHERE id = ?
                """, arguments: [jpoId])
        }

        // JPO alone: date present, but not old enough for the aged tint.
        let jpoOnly = try service.getAllBadgeCounts(userId: env.adminUserId)
        #expect(jpoOnly.oldestPendingDate != nil,
            "Pending JPOs must still populate oldestPendingDate (existing behavior)")
        #expect(jpoOnly.hasOldItems == false,
            "A 3-day-old JPO is within the 7-day threshold")

        // Add a 20-day-old deletion approval — the overall oldest must win.
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO scheduled_deletions
                    (entity_type, entity_id, entity_name, status, created_at)
                VALUES ('part', 998, 'Ancient Deletion', 'pending_approval', datetime('now', '-20 days'))
                """)
        }
        let deletionCreatedAt = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT created_at FROM scheduled_deletions WHERE entity_id = 998")
        }

        let combined = try service.getAllBadgeCounts(userId: env.adminUserId)
        #expect(combined.oldestPendingDate == deletionCreatedAt,
            "oldestPendingDate must be the overall oldest item across every pending queue")
        #expect(combined.hasOldItems == true)
    }

    @Test("hasOldItems parses SQLite datetime('now') space-separated timestamps")
    func testHasOldItemsParsesSpaceFormatTimestamps() {
        // Rows created via SQLite column defaults store 'YYYY-MM-DD HH:MM:SS'
        // (no 'T', no zone). parseISO rejected these, silently disabling the
        // aged tint for default-stamped queues (#708).
        let counts = BadgeCountService.BadgeCounts(oldestPendingDate: "2020-01-01 00:00:00")
        #expect(counts.hasOldItems == true)
    }

    // MARK: - SQLite timestamps must parse as UTC, not device-local (#708 / PR #1354 review)
    //
    // SQLite's datetime('now') / CURRENT_TIMESTAMP defaults are always UTC but
    // carry no zone marker. Parsing them with a zone-less local formatter skews
    // every age comparison by the device's UTC offset.

    @Test("parseDateTimeUTC maps zone-less SQLite timestamps to exact UTC instants")
    func testParseDateTimeUTCIsDeterministic() throws {
        // 2020-01-01T00:00:00Z == epoch 1577836800. Device-local parsing only
        // yields this instant when the device happens to be in UTC, so this
        // assertion fails under local-tz parsing on any offset device
        // (e.g. a +6 device would produce epoch 1577815200 instead).
        let space = try #require(CoreFormatters.parseDateTimeUTC("2020-01-01 00:00:00"))
        #expect(space.timeIntervalSince1970 == 1_577_836_800)

        let tSeparated = try #require(CoreFormatters.parseDateTimeUTC("2020-01-01T00:00:00"))
        #expect(tSeparated.timeIntervalSince1970 == 1_577_836_800)

        // Zone-carrying ISO input parses identically to parseDateTime.
        let iso = try #require(CoreFormatters.parseDateTimeUTC("2020-01-01T00:00:00Z"))
        #expect(iso.timeIntervalSince1970 == 1_577_836_800)
    }

    @Test("hasOldItems 7-day threshold is exact for UTC SQLite timestamps on any device zone")
    func testHasOldItemsThresholdImmuneToDeviceZone() {
        // Format timestamps exactly how SQLite defaults store them: UTC,
        // space-separated, no zone marker.
        let sqliteUTC = DateFormatter()
        sqliteUTC.dateFormat = "yyyy-MM-dd HH:mm:ss"
        sqliteUTC.timeZone = TimeZone(identifier: "UTC")
        sqliteUTC.locale = Locale(identifier: "en_US_POSIX")

        // 7 days + 2 hours old: must be aged. Under device-local parsing on a
        // west-of-UTC device (e.g. UTC-6) the item would look only ~6d20h old
        // and this expectation fails.
        let justOverThreshold = Date().addingTimeInterval(-(7 * 86400 + 2 * 3600))
        let overCounts = BadgeCountService.BadgeCounts(
            oldestPendingDate: sqliteUTC.string(from: justOverThreshold)
        )
        #expect(overCounts.hasOldItems == true,
            "A 7d2h-old UTC timestamp must trip the 7-day threshold regardless of device time zone")

        // 6 days + 22 hours old: must NOT be aged. Under device-local parsing
        // on an east-of-UTC device (e.g. UTC+6) the item would look ~7d4h old
        // and this expectation fails. Together the two cases catch local-tz
        // parsing on any non-UTC device.
        let justUnderThreshold = Date().addingTimeInterval(-(6 * 86400 + 22 * 3600))
        let underCounts = BadgeCountService.BadgeCounts(
            oldestPendingDate: sqliteUTC.string(from: justUnderThreshold)
        )
        #expect(underCounts.hasOldItems == false,
            "A 6d22h-old UTC timestamp must stay under the 7-day threshold regardless of device time zone")
    }
}
