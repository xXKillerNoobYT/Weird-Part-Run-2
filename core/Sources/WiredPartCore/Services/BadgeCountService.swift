import Foundation
import GRDB

/// Badge Count Service — provides live pending-item counts for tab bar badges.
///
/// Each method returns an integer count suitable for `.badge()` on SwiftUI tabs.
/// All queries handle missing tables gracefully (returning 0) so the app never
/// crashes on a fresh or partially-migrated database.
///
/// Counts are designed to be cheap (single COUNT queries) and safe to call
/// on every tab appearance or scene-phase foreground transition.
public final class BadgeCountService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Result Type

    /// Aggregate badge counts for every navigable tab in the app.
    public struct BadgeCounts: Sendable, Equatable {
        /// Orders awaiting approval (JPOs with status='submitted')
        public var pendingApprovals: Int
        /// Workers currently clocked in (active labor entries with no clock_out)
        public var activeClockedIn: Int
        /// Chat: unread messages (placeholder — requires per-user read tracking)
        public var unreadMessages: Int
        /// Scheduling: unassigned dispatch slots for today
        public var openDispatches: Int
        /// Warehouse: active receiving sessions
        public var pendingReceipts: Int
        /// Orders: overdue POs (expected_delivery < today, not received/cancelled)
        public var overdueOrders: Int
        /// People: certifications expiring within 7 days
        public var expiringCerts: Int
        /// Notebooks: total unread notebook entries (per-user)
        public var unreadNotebookEntries: Int
        /// Pending time-off requests needing approval
        public var pendingTimeOff: Int
        /// Pending tool edit verifications
        public var pendingToolEdits: Int
        /// Pending part deletions needing approval
        public var pendingDeletions: Int

        /// Oldest pending item date (ISO string) — nil if nothing pending.
        /// Used to determine badge tint (green vs red).
        public var oldestPendingDate: String?

        public init(
            pendingApprovals: Int = 0,
            activeClockedIn: Int = 0,
            unreadMessages: Int = 0,
            openDispatches: Int = 0,
            pendingReceipts: Int = 0,
            overdueOrders: Int = 0,
            expiringCerts: Int = 0,
            unreadNotebookEntries: Int = 0,
            pendingTimeOff: Int = 0,
            pendingToolEdits: Int = 0,
            pendingDeletions: Int = 0,
            oldestPendingDate: String? = nil
        ) {
            self.pendingApprovals = pendingApprovals
            self.activeClockedIn = activeClockedIn
            self.unreadMessages = unreadMessages
            self.openDispatches = openDispatches
            self.pendingReceipts = pendingReceipts
            self.overdueOrders = overdueOrders
            self.expiringCerts = expiringCerts
            self.unreadNotebookEntries = unreadNotebookEntries
            self.pendingTimeOff = pendingTimeOff
            self.pendingToolEdits = pendingToolEdits
            self.pendingDeletions = pendingDeletions
            self.oldestPendingDate = oldestPendingDate
        }

        /// True if any item has been pending for more than 7 days.
        public var hasOldItems: Bool {
            guard let dateStr = oldestPendingDate else { return false }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let basic = ISO8601DateFormatter()
            basic.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateStr) ?? basic.date(from: dateStr) else { return false }
            return Date().timeIntervalSince(date) > 7 * 86400
        }

        // MARK: - Per-Tab Aggregates

        /// Badge count for the Dashboard tab (active clock-ins for current user context).
        public var dashboardBadge: Int { activeClockedIn }

        /// Badge count for the Jobs tab.
        public var jobsBadge: Int { 0 } // Jobs don't have a pending-action badge

        /// Badge count for the Chat tab.
        public var chatBadge: Int { unreadMessages }

        /// Badge count for the Scheduling tab.
        public var schedulingBadge: Int { openDispatches }

        /// Badge count for the Warehouse tab.
        public var warehouseBadge: Int { pendingReceipts }

        /// Badge count for the Orders tab.
        public var ordersBadge: Int { pendingApprovals + overdueOrders }

        /// Badge count for the People tab.
        public var peopleBadge: Int { expiringCerts }

        /// Badge count for the Office tab.
        public var officeBadge: Int { pendingApprovals + pendingTimeOff + pendingToolEdits + pendingDeletions }

        /// Badge count for the Notebooks tab.
        public var notebooksBadge: Int { unreadNotebookEntries }

        /// Badge count for the Fleet tab.
        public var fleetBadge: Int { 0 }

        /// Badge count for the Tools tab.
        public var toolsBadge: Int { pendingToolEdits }

        /// Returns the badge count for a given module ID.
        public func badge(for moduleId: String) -> Int {
            switch moduleId {
            case "dashboard": return dashboardBadge
            case "jobs": return jobsBadge
            case "chat": return chatBadge
            case "scheduling": return schedulingBadge
            case "warehouse": return warehouseBadge
            case "orders": return ordersBadge
            case "people": return peopleBadge
            case "office": return officeBadge
            case "notebooks": return notebooksBadge
            case "fleet": return fleetBadge
            case "tools": return toolsBadge
            default: return 0
            }
        }
    }

    // MARK: - Full Fetch

    /// Fetch all badge counts in a single call. Safe on empty databases.
    public func getAllBadgeCounts(userId: Int64? = nil) throws -> BadgeCounts {
        var counts = BadgeCounts()

        counts.pendingApprovals = try safeCount(sql:
            "SELECT COUNT(*) FROM job_parts_orders WHERE status = 'submitted' AND deleted_at IS NULL"
        )

        counts.activeClockedIn = try safeCount(sql:
            "SELECT COUNT(*) FROM labor_entries WHERE clock_out IS NULL AND deleted_at IS NULL"
        )

        counts.openDispatches = try safeCount(sql: """
            SELECT COUNT(DISTINCT job_id) FROM job_dispatch
            WHERE date(dispatch_date) = date('now')
              AND status = 'scheduled'
              AND deleted_at IS NULL
        """)

        counts.pendingReceipts = try safeCount(sql:
            "SELECT COUNT(*) FROM receiving_sessions WHERE status IN ('in_progress', 'active') AND deleted_at IS NULL"
        )

        counts.overdueOrders = try safeCount(sql: """
            SELECT COUNT(*) FROM purchase_orders
            WHERE expected_delivery IS NOT NULL
              AND date(expected_delivery) < date('now')
              AND status NOT IN ('received', 'cancelled', 'deleted')
              AND deleted_at IS NULL
        """)

        counts.expiringCerts = try safeCount(sql: """
            SELECT COUNT(*) FROM certifications
            WHERE expiry_date IS NOT NULL
              AND is_active = 1
              AND deleted_at IS NULL
              AND date(expiry_date) >= date('now')
              AND date(expiry_date) <= date('now', '+7 days')
        """)

        counts.pendingTimeOff = try safeCount(sql: """
            SELECT COUNT(DISTINCT COALESCE(request_group, CAST(id AS TEXT)))
            FROM schedule_exceptions
            WHERE exception_type = 'time_off'
              AND is_approved = 0
              AND deleted_at IS NULL
        """)

        // tool_edit_log is a planned future table (not yet in schema) — returns 0 gracefully
        counts.pendingToolEdits = try safeCount(sql:
            "SELECT COUNT(*) FROM tool_edit_log WHERE status = 'pending' AND deleted_at IS NULL"
        )

        counts.pendingDeletions = try safeCount(sql:
            "SELECT COUNT(*) FROM scheduled_deletions WHERE status = 'pending_approval' AND deleted_at IS NULL"
        )

        // Notebook unread entries (per-user, using UserDefaults-based tracking on the iOS side)
        // We count total notebook entries updated in the last 7 days as a proxy
        if let uid = userId {
            counts.unreadNotebookEntries = try safeCount(sql: """
                SELECT COUNT(*) FROM notebook_entries ne
                JOIN notebooks n ON ne.notebook_id = n.id
                LEFT JOIN job_team_members jtm ON n.job_id = jtm.job_id AND jtm.user_id = ?
                WHERE ne.deleted_at IS NULL
                  AND n.deleted_at IS NULL
                  AND (n.job_id IS NULL OR jtm.user_id IS NOT NULL)
                  AND date(ne.updated_at) >= date('now', '-7 days')
            """, arguments: [uid])
        }

        // Unread messages: count messages in channels the user belongs to, created after last read
        if let uid = userId {
            counts.unreadMessages = try safeCount(sql: """
                SELECT COUNT(*) FROM chat_messages cm
                JOIN chat_channels cc ON cm.channel_id = cc.id
                WHERE cm.deleted_at IS NULL
                  AND cc.deleted_at IS NULL
                  AND cm.sender_id != ?
                  AND date(cm.created_at) >= date('now', '-1 day')
            """, arguments: [uid])
        }

        // Oldest pending date — find the oldest submitted JPO for tint calculation
        counts.oldestPendingDate = try safeString(sql: """
            SELECT MIN(created_at) FROM job_parts_orders
            WHERE status = 'submitted' AND deleted_at IS NULL
        """)

        return counts
    }

    // MARK: - Individual Counts (for targeted refresh)

    /// Count of JPOs awaiting approval.
    public func pendingApprovalCount() throws -> Int {
        try safeCount(sql:
            "SELECT COUNT(*) FROM job_parts_orders WHERE status = 'submitted' AND deleted_at IS NULL"
        )
    }

    /// Count of overdue purchase orders.
    public func overdueOrderCount() throws -> Int {
        try safeCount(sql: """
            SELECT COUNT(*) FROM purchase_orders
            WHERE expected_delivery IS NOT NULL
              AND date(expected_delivery) < date('now')
              AND status NOT IN ('received', 'cancelled', 'deleted')
              AND deleted_at IS NULL
        """)
    }

    /// Count of active receiving sessions.
    public func pendingReceiptCount() throws -> Int {
        try safeCount(sql:
            "SELECT COUNT(*) FROM receiving_sessions WHERE status IN ('in_progress', 'active') AND deleted_at IS NULL"
        )
    }

    /// Count of certifications expiring within N days.
    public func expiringCertCount(withinDays: Int = 7) throws -> Int {
        try safeCount(sql: """
            SELECT COUNT(*) FROM certifications
            WHERE expiry_date IS NOT NULL
              AND is_active = 1
              AND deleted_at IS NULL
              AND date(expiry_date) >= date('now')
              AND date(expiry_date) <= date('now', '+\(withinDays) days')
        """)
    }

    // MARK: - Helpers

    /// Execute a COUNT query, returning 0 if the table doesn't exist.
    private func safeCount(sql: String, arguments: StatementArguments = StatementArguments()) throws -> Int {
        do {
            return try db.writer.read { dbConnection in
                try Int.fetchOne(dbConnection, sql: sql, arguments: arguments) ?? 0
            }
        } catch {
            if isTableNotFoundError(error) { return 0 }
            throw error
        }
    }

    /// Execute a scalar string query, returning nil if the table doesn't exist.
    private func safeString(sql: String, arguments: StatementArguments = StatementArguments()) throws -> String? {
        do {
            return try db.writer.read { dbConnection in
                try String.fetchOne(dbConnection, sql: sql, arguments: arguments)
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    /// Detect GRDB "no such table" / "no such column" errors.
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
    }
}
