import Foundation
import GRDB

/// Chat & Q&A Service — channels, messages, Q&A threads, RFIs, and chat stats.
///
/// All queries run against the local SQLite database via GRDB.
/// Tables that may not yet exist are handled gracefully: queries that
/// hit a missing table return zero counts or empty arrays rather than throwing.
///
/// Ported from: Chat & Q&A feature area (Phase 9)
public final class ChatService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // =========================================================================
    // MARK: - Error Types
    // =========================================================================

    public enum ChatError: Error, Sendable {
        case channelNotFound(Int64)
        case messageNotFound(Int64)
        case threadNotFound(Int64)
    }

    // =========================================================================
    // MARK: - Result Types
    // =========================================================================

    /// A channel row for list views with summary info.
    public struct ChannelListItem: Sendable, Identifiable {
        public let id: Int64
        public let name: String?
        public let channelType: String
        public let jobName: String?
        public let memberCount: Int
        public let lastMessageAt: String?

        public init(
            id: Int64, name: String?, channelType: String, jobName: String?,
            memberCount: Int, lastMessageAt: String?
        ) {
            self.id = id
            self.name = name
            self.channelType = channelType
            self.jobName = jobName
            self.memberCount = memberCount
            self.lastMessageAt = lastMessageAt
        }
    }

    /// A message row enriched with sender name.
    public struct MessageRow: Sendable, Identifiable {
        public let id: Int64
        public let senderId: Int64
        public let senderName: String
        public let content: String
        public let messageType: String
        public let createdAt: String?

        public init(
            id: Int64, senderId: Int64, senderName: String, content: String,
            messageType: String, createdAt: String?
        ) {
            self.id = id
            self.senderId = senderId
            self.senderName = senderName
            self.content = content
            self.messageType = messageType
            self.createdAt = createdAt
        }
    }

    /// A Q&A thread row enriched with user names.
    public struct QAThreadRow: Sendable, Identifiable {
        public let id: Int64
        public let jobId: Int64
        public let question: String
        public let askedByName: String
        public let currentLevel: String
        public let status: String
        public let priority: String
        public let answer: String?
        public let answeredByName: String?

        public init(
            id: Int64, jobId: Int64 = 0, question: String, askedByName: String,
            currentLevel: String, status: String, priority: String,
            answer: String?, answeredByName: String?
        ) {
            self.id = id
            self.jobId = jobId
            self.question = question
            self.askedByName = askedByName
            self.currentLevel = currentLevel
            self.status = status
            self.priority = priority
            self.answer = answer
            self.answeredByName = answeredByName
        }
    }

    /// Aggregate chat statistics.
    public struct ChatStats: Sendable {
        public let totalChannels: Int
        public let unreadMentions: Int
        public let openQuestions: Int

        public init(totalChannels: Int, unreadMentions: Int, openQuestions: Int) {
            self.totalChannels = totalChannels
            self.unreadMentions = unreadMentions
            self.openQuestions = openQuestions
        }
    }

    // =========================================================================
    // MARK: - 1. Channels
    // =========================================================================

    /// List chat channels that a user is a member of, with member count and last message time.
    public func listChannels(userId: Int64) throws -> [ChannelListItem] {
        do {
            return try db.writer.read { dbConn -> [ChannelListItem] in
                let sql = """
                    SELECT cc.id, cc.name, cc.channel_type,
                           j.job_name,
                           COALESCE((SELECT COUNT(*) FROM chat_channel_members ccm
                                     WHERE ccm.channel_id = cc.id AND ccm.left_at IS NULL AND ccm.deleted_at IS NULL), 0) AS member_count,
                           (SELECT MAX(cm.created_at) FROM chat_messages cm
                            WHERE cm.channel_id = cc.id AND cm.deleted_at IS NULL) AS last_message_at
                    FROM chat_channels cc
                    INNER JOIN chat_channel_members mem
                        ON mem.channel_id = cc.id AND mem.user_id = ? AND mem.left_at IS NULL AND mem.deleted_at IS NULL
                    LEFT JOIN jobs j ON j.id = cc.job_id
                    WHERE cc.is_active = 1 AND cc.deleted_at IS NULL
                    ORDER BY last_message_at DESC NULLS LAST, cc.created_at DESC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [userId])
                return rows.map { row in
                    ChannelListItem(
                        id: row["id"] ?? 0,
                        name: row["name"] as String?,
                        channelType: row["channel_type"] ?? "group",
                        jobName: row["job_name"] as String?,
                        memberCount: row["member_count"] ?? 0,
                        lastMessageAt: row["last_message_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 2. Messages
    // =========================================================================

    /// Get messages for a channel, most recent first.
    public func getMessages(channelId: Int64, limit: Int = 50) throws -> [MessageRow] {
        do {
            return try db.writer.read { dbConn -> [MessageRow] in
                let sql = """
                    SELECT cm.id, cm.sender_id, cm.content, cm.message_type, cm.created_at,
                           COALESCE(u.display_name, u.email, 'Unknown') AS sender_name
                    FROM chat_messages cm
                    LEFT JOIN users u ON u.id = cm.sender_id
                    WHERE cm.channel_id = ? AND cm.deleted_at IS NULL
                    ORDER BY cm.created_at DESC
                    LIMIT ?
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [channelId, limit])
                return rows.map { row in
                    MessageRow(
                        id: row["id"] ?? 0,
                        senderId: row["sender_id"] ?? 0,
                        senderName: row["sender_name"] ?? "Unknown",
                        content: row["content"] ?? "",
                        messageType: row["message_type"] ?? "text",
                        createdAt: row["created_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Send a message to a channel. Returns the inserted message row ID.
    @discardableResult
    public func sendMessage(channelId: Int64, senderId: Int64, content: String) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO chat_messages
                    (channel_id, sender_id, message_type, content, created_at)
                    VALUES (?, ?, 'text', ?, datetime('now'))
                    """,
                arguments: [channelId, senderId, content]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Creates a new chat channel.
    @discardableResult
    public func createChannel(
        name: String,
        channelType: String = "group",
        jobId: Int64? = nil,
        createdBy: Int64
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO chat_channels
                    (channel_type, job_id, name, created_by, is_active, created_at, updated_at)
                    VALUES (?, ?, ?, ?, 1, datetime('now'), datetime('now'))
                    """,
                arguments: [channelType, jobId, name, createdBy]
            )
            let channelId = dbConn.lastInsertedRowID
            // Add creator as member
            try dbConn.execute(
                sql: """
                    INSERT INTO chat_channel_members
                    (channel_id, user_id, role, joined_at)
                    VALUES (?, ?, 'admin', datetime('now'))
                    """,
                arguments: [channelId, createdBy]
            )
            return channelId
        }
    }

    // =========================================================================
    // MARK: - 3. Q&A Threads
    // =========================================================================

    /// List Q&A threads with optional status filter.
    public func listQAThreads(status: String? = nil) throws -> [QAThreadRow] {
        do {
            return try db.writer.read { dbConn -> [QAThreadRow] in
                var whereClauses = ["qa.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let status, !status.isEmpty {
                    whereClauses.append("qa.status = ?")
                    args.append(status)
                }

                let sql = """
                    SELECT qa.id, COALESCE(qa.job_id, 0) AS job_id, qa.subject, qa.current_level, qa.status, qa.priority,
                           qa.answer_text,
                           COALESCE(ua.display_name, ua.email, 'Unknown') AS asked_by_name,
                           COALESCE(ub.display_name, ub.email) AS answered_by_name
                    FROM qa_threads qa
                    LEFT JOIN users ua ON ua.id = qa.asked_by
                    LEFT JOIN users ub ON ub.id = qa.answered_by
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY qa.created_at DESC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    QAThreadRow(
                        id: row["id"] ?? 0,
                        jobId: row["job_id"] ?? 0,
                        question: row["subject"] ?? "",
                        askedByName: row["asked_by_name"] ?? "Unknown",
                        currentLevel: row["current_level"] ?? "field",
                        status: row["status"] ?? "open",
                        priority: row["priority"] ?? "normal",
                        answer: row["answer_text"] as String?,
                        answeredByName: row["answered_by_name"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// List Q&A threads for a specific job with optional status filter.
    public func listQAThreads(jobId: Int64, status: String? = nil) throws -> [QAThreadRow] {
        do {
            return try db.writer.read { dbConn -> [QAThreadRow] in
                var whereClauses = ["qa.deleted_at IS NULL", "qa.job_id = ?"]
                var args: [DatabaseValueConvertible?] = [jobId]

                if let status, !status.isEmpty {
                    whereClauses.append("qa.status = ?")
                    args.append(status)
                }

                let sql = """
                    SELECT qa.id, COALESCE(qa.job_id, 0) AS job_id, qa.subject, qa.current_level, qa.status, qa.priority,
                           qa.answer_text,
                           COALESCE(ua.display_name, ua.email, 'Unknown') AS asked_by_name,
                           COALESCE(ub.display_name, ub.email) AS answered_by_name
                    FROM qa_threads qa
                    LEFT JOIN users ua ON ua.id = qa.asked_by
                    LEFT JOIN users ub ON ub.id = qa.answered_by
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY qa.created_at DESC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    QAThreadRow(
                        id: row["id"] ?? 0,
                        jobId: row["job_id"] ?? 0,
                        question: row["subject"] ?? "",
                        askedByName: row["asked_by_name"] ?? "Unknown",
                        currentLevel: row["current_level"] ?? "field",
                        status: row["status"] ?? "open",
                        priority: row["priority"] ?? "normal",
                        answer: row["answer_text"] as String?,
                        answeredByName: row["answered_by_name"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Create a new Q&A thread. Returns the inserted row ID.
    @discardableResult
    public func createQAThread(
        jobId: Int64,
        askedBy: Int64,
        subject: String,
        priority: String = "normal"
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO qa_threads
                    (job_id, asked_by, subject, current_level, status, priority, created_at, updated_at)
                    VALUES (?, ?, ?, 'worker', 'open', ?, datetime('now'), datetime('now'))
                    """,
                arguments: [jobId, askedBy, subject, priority]
            )
            return dbConn.lastInsertedRowID
        }
    }

    // =========================================================================
    // MARK: - 4. Chat Stats
    // =========================================================================

    /// Get aggregate chat statistics: total channels, unread mentions, open questions.
    public func getChatStats() throws -> ChatStats {
        let totalChannels = try safeCount(
            sql: "SELECT COUNT(*) FROM chat_channels WHERE is_active = 1 AND deleted_at IS NULL"
        )

        let unreadMentions = try safeCount(
            sql: "SELECT COUNT(*) FROM chat_mentions WHERE acknowledged_at IS NULL AND deleted_at IS NULL"
        )

        let openQuestions = try safeCount(
            sql: "SELECT COUNT(*) FROM qa_threads WHERE status = 'open' AND deleted_at IS NULL"
        )

        return ChatStats(
            totalChannels: totalChannels,
            unreadMentions: unreadMentions,
            openQuestions: openQuestions
        )
    }

    // =========================================================================
    // MARK: - Internal Helpers
    // =========================================================================

    /// Execute a SELECT COUNT(*) query returning an Int.
    /// Returns 0 if the table does not exist.
    private func safeCount(sql: String, arguments: StatementArguments = StatementArguments()) throws -> Int {
        do {
            return try db.writer.read { dbConn in
                try Int.fetchOne(dbConn, sql: sql, arguments: arguments) ?? 0
            }
        } catch {
            if isTableNotFoundError(error) { return 0 }
            throw error
        }
    }

    /// Detect whether a GRDB/SQLite error indicates a missing table.
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table")
    }

    // =========================================================================
    // MARK: - Supplier Communication Bridge
    // =========================================================================

    /// Data for a supplier channel listing.
    public struct SupplierChannelRow: Sendable {
        public let channelId: Int64
        public let channelName: String
        public let supplierName: String
        public let supplierId: Int64
        public let bridgeDisplayName: String
        public let role: String?
        public let lastMessageAt: String?
        public let unreadCount: Int
    }

    /// Create a supplier channel and bridge link, optionally linked to a job.
    /// Returns the channel ID.
    public func createSupplierChannel(
        name: String,
        supplierId: Int64,
        supplierDisplayName: String,
        contactId: Int64?,
        role: String?,
        createdBy: Int64,
        jobId: Int64? = nil
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            // Create the channel with type "supplier" and optional job link
            try dbConn.execute(sql: """
                INSERT INTO chat_channels (channel_type, job_id, name, created_by, is_active, created_at)
                VALUES ('supplier', ?, ?, ?, 1, datetime('now'))
                """, arguments: [jobId, name, createdBy])
            let channelId = dbConn.lastInsertedRowID

            // Add the creator as a channel member (admin)
            try dbConn.execute(sql: """
                INSERT INTO chat_channel_members (channel_id, user_id, role, joined_at)
                VALUES (?, ?, 'admin', datetime('now'))
                """, arguments: [channelId, createdBy])

            // Create the bridge link
            let token = UUID().uuidString
            try dbConn.execute(sql: """
                INSERT INTO supplier_channel_bridges
                (channel_id, supplier_id, contact_id, display_name, role, invite_token, is_active, created_at)
                VALUES (?, ?, ?, ?, ?, ?, 1, datetime('now'))
                """, arguments: [channelId, supplierId, contactId, supplierDisplayName, role, token])

            return channelId
        }
    }

    /// List all supplier channels for the current user.
    public func listSupplierChannels(userId: Int64) throws -> [SupplierChannelRow] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT cc.id AS channel_id, cc.name AS channel_name,
                       s.name AS supplier_name, scb.supplier_id,
                       scb.display_name, scb.role,
                       (SELECT MAX(created_at) FROM chat_messages WHERE channel_id = cc.id AND deleted_at IS NULL) AS last_message_at,
                       (SELECT COUNT(*) FROM chat_messages cm
                        WHERE cm.channel_id = cc.id AND cm.deleted_at IS NULL
                        AND cm.created_at > COALESCE(
                            (SELECT read_at FROM chat_read_receipts WHERE channel_id = cc.id AND user_id = ?), '1970-01-01'
                        )) AS unread_count
                FROM chat_channels cc
                JOIN chat_channel_members ccm ON ccm.channel_id = cc.id AND ccm.user_id = ?
                JOIN supplier_channel_bridges scb ON scb.channel_id = cc.id AND scb.deleted_at IS NULL
                JOIN suppliers s ON s.id = scb.supplier_id AND s.deleted_at IS NULL
                WHERE cc.channel_type = 'supplier' AND cc.deleted_at IS NULL
                ORDER BY last_message_at DESC NULLS LAST
                """, arguments: [userId, userId])

            return rows.map { row in
                SupplierChannelRow(
                    channelId: row["channel_id"],
                    channelName: row["channel_name"] ?? "",
                    supplierName: row["supplier_name"] ?? "",
                    supplierId: row["supplier_id"],
                    bridgeDisplayName: row["display_name"] ?? "",
                    role: row["role"],
                    lastMessageAt: row["last_message_at"],
                    unreadCount: row["unread_count"] ?? 0
                )
            }
        }
    }

    /// Send a message in a supplier channel with direction tracking.
    public func sendSupplierMessage(
        channelId: Int64,
        senderId: Int64,
        content: String,
        direction: String,
        attachmentType: String? = nil,
        attachmentRef: String? = nil
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            // Send as regular chat message
            try dbConn.execute(sql: """
                INSERT INTO chat_messages (channel_id, sender_id, message_type, content, created_at)
                VALUES (?, ?, 'text', ?, datetime('now'))
                """, arguments: [channelId, senderId, content])
            let messageId = dbConn.lastInsertedRowID

            // Get bridge for this channel
            let bridge = try Row.fetchOne(dbConn, sql: """
                SELECT id FROM supplier_channel_bridges
                WHERE channel_id = ? AND deleted_at IS NULL LIMIT 1
                """, arguments: [channelId])

            if let bridgeId: Int64 = bridge?["id"] {
                try dbConn.execute(sql: """
                    INSERT INTO supplier_messages
                    (message_id, bridge_id, direction, attachment_type, attachment_ref, created_at)
                    VALUES (?, ?, ?, ?, ?, datetime('now'))
                    """, arguments: [messageId, bridgeId, direction, attachmentType, attachmentRef])
            }

            return messageId
        }
    }

    /// Add an internal user to a supplier channel.
    public func addUserToSupplierChannel(channelId: Int64, userId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT OR IGNORE INTO chat_channel_members (channel_id, user_id, role, joined_at)
                VALUES (?, ?, 'member', datetime('now'))
                """, arguments: [channelId, userId])
        }
    }

    /// Get supplier bridge info for a channel.
    public func getSupplierBridge(channelId: Int64) throws -> SupplierChannelBridge? {
        try db.writer.read { dbConn in
            try SupplierChannelBridge.fetchOne(dbConn, sql: """
                SELECT * FROM supplier_channel_bridges
                WHERE channel_id = ? AND deleted_at IS NULL
                """, arguments: [channelId])
        }
    }

    /// List supplier channels linked to a specific job.
    public func listSupplierChannelsForJob(jobId: Int64, userId: Int64) throws -> [SupplierChannelRow] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT cc.id AS channel_id, cc.name AS channel_name,
                       s.name AS supplier_name, scb.supplier_id,
                       scb.display_name, scb.role,
                       (SELECT MAX(created_at) FROM chat_messages WHERE channel_id = cc.id AND deleted_at IS NULL) AS last_message_at,
                       (SELECT COUNT(*) FROM chat_messages cm
                        WHERE cm.channel_id = cc.id AND cm.deleted_at IS NULL
                        AND cm.created_at > COALESCE(
                            (SELECT read_at FROM chat_read_receipts WHERE channel_id = cc.id AND user_id = ?), '1970-01-01'
                        )) AS unread_count
                FROM chat_channels cc
                JOIN supplier_channel_bridges scb ON scb.channel_id = cc.id AND scb.deleted_at IS NULL
                JOIN suppliers s ON s.id = scb.supplier_id AND s.deleted_at IS NULL
                WHERE cc.channel_type = 'supplier' AND cc.job_id = ? AND cc.deleted_at IS NULL
                ORDER BY last_message_at DESC NULLS LAST
                """, arguments: [userId, jobId])

            return rows.map { row in
                SupplierChannelRow(
                    channelId: row["channel_id"],
                    channelName: row["channel_name"] ?? "",
                    supplierName: row["supplier_name"] ?? "",
                    supplierId: row["supplier_id"],
                    bridgeDisplayName: row["display_name"] ?? "",
                    role: row["role"],
                    lastMessageAt: row["last_message_at"],
                    unreadCount: row["unread_count"] ?? 0
                )
            }
        }
    }

    /// Create a Q&A thread linked to a supplier channel for RFI purposes.
    @discardableResult
    public func createSupplierQuestion(
        channelId: Int64,
        jobId: Int64,
        askedBy: Int64,
        subject: String,
        priority: String = "normal"
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO qa_threads (channel_id, job_id, asked_by, subject, current_level, status, priority, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'worker', 'open', ?, datetime('now'), datetime('now'))
                """, arguments: [channelId, jobId, askedBy, subject, priority])
            return dbConn.lastInsertedRowID
        }
    }

    /// A supplier question row combining Q&A thread info with supplier context.
    public struct SupplierQuestionRow: Sendable, Identifiable {
        public let id: Int64
        public let subject: String
        public let supplierName: String
        public let status: String
        public let priority: String
        public let askedByName: String
        public let jobName: String?
    }

    /// List Q&A threads that belong to supplier channels.
    public func listSupplierQuestions(status: String? = nil) throws -> [SupplierQuestionRow] {
        do {
            return try db.writer.read { dbConn -> [SupplierQuestionRow] in
                var whereClauses = ["qa.deleted_at IS NULL", "cc.channel_type = 'supplier'"]
                var args: [DatabaseValueConvertible?] = []

                if let status, !status.isEmpty {
                    whereClauses.append("qa.status = ?")
                    args.append(status)
                }

                let sql = """
                    SELECT qa.id, qa.subject, qa.status, qa.priority,
                           COALESCE(ua.display_name, ua.email, 'Unknown') AS asked_by_name,
                           s.name AS supplier_name,
                           j.job_name
                    FROM qa_threads qa
                    JOIN chat_channels cc ON cc.id = qa.channel_id
                    JOIN supplier_channel_bridges scb ON scb.channel_id = cc.id AND scb.deleted_at IS NULL
                    JOIN suppliers s ON s.id = scb.supplier_id AND s.deleted_at IS NULL
                    LEFT JOIN users ua ON ua.id = qa.asked_by
                    LEFT JOIN jobs j ON j.id = qa.job_id
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY qa.created_at DESC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    SupplierQuestionRow(
                        id: row["id"] ?? 0,
                        subject: row["subject"] ?? "",
                        supplierName: row["supplier_name"] ?? "",
                        status: row["status"] ?? "open",
                        priority: row["priority"] ?? "normal",
                        askedByName: row["asked_by_name"] ?? "Unknown",
                        jobName: row["job_name"]
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Deactivate a supplier channel bridge (soft delete).
    public func deactivateSupplierBridge(channelId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE supplier_channel_bridges SET is_active = 0, deleted_at = datetime('now')
                WHERE channel_id = ?
                """, arguments: [channelId])
        }
    }

    // MARK: - Supplier Bridge Settings

    /// Row data for a supplier communication bridge (settings page).
    public struct SupplierBridgeRow: Sendable, Identifiable {
        public let id: String
        public let supplierName: String
        public let status: String
        public let protocol_: String
        public let lastSyncAt: String?
    }

    /// List all supplier communication bridges with supplier names.
    public func listSupplierBridges() throws -> [SupplierBridgeRow] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT sb.id, sb.status, sb.protocol, sb.last_sync_at,
                           COALESCE(s.name, 'Unknown Supplier') AS supplier_name
                    FROM supplier_bridges sb
                    LEFT JOIN suppliers s ON s.id = sb.supplier_id
                    ORDER BY s.name ASC
                """)
                return rows.map { row in
                    SupplierBridgeRow(
                        id: "\(row["id"] as Int64? ?? 0)",
                        supplierName: row["supplier_name"] as? String ?? "Unknown",
                        status: row["status"] as? String ?? "unknown",
                        protocol_: row["protocol"] as? String ?? "HTTP",
                        lastSyncAt: row["last_sync_at"] as? String
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }
}
