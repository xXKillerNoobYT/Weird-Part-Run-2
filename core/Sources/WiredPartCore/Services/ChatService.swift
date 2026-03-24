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

    // MARK: - Unified Inbox

    /// An inbox item representing a channel with last message info and unread count.
    public struct InboxItem: Sendable, Identifiable {
        public let id: Int64       // channel ID
        public let channelName: String
        public let channelType: String
        public let lastMessagePreview: String
        public let lastMessageDate: String?
        public let lastMessageBy: String?
        public let unreadCount: Int
        public let jobId: Int64?
        public let jobName: String?
        public let memberCount: Int
    }

    /// Get unified inbox showing all channels with last message info and unread counts.
    /// Sorted by unread first, then most recent activity.
    public func getUnifiedInbox(userId: Int64) throws -> [InboxItem] {
        do {
            return try db.writer.read { dbConn -> [InboxItem] in
                let sql = """
                    SELECT
                        cc.id AS channel_id,
                        COALESCE(cc.name, j.job_name, 'Direct Message') AS channel_name,
                        cc.channel_type,
                        cc.job_id,
                        j.job_name,
                        COALESCE(last_msg.content, 'No messages yet') AS last_message,
                        last_msg.created_at AS last_message_date,
                        COALESCE(last_msg_user.display_name, last_msg_user.email) AS last_message_by,
                        COALESCE(unread.cnt, 0) AS unread_count,
                        COALESCE(mem_count.cnt, 0) AS member_count
                    FROM chat_channels cc
                    INNER JOIN chat_channel_members my_mem
                        ON my_mem.channel_id = cc.id
                        AND my_mem.user_id = ?
                        AND my_mem.left_at IS NULL
                        AND my_mem.deleted_at IS NULL
                    LEFT JOIN jobs j ON j.id = cc.job_id
                    LEFT JOIN (
                        SELECT cm.channel_id, cm.content, cm.created_at, cm.sender_id,
                               ROW_NUMBER() OVER (PARTITION BY cm.channel_id ORDER BY cm.created_at DESC) AS rn
                        FROM chat_messages cm
                        WHERE cm.deleted_at IS NULL
                    ) last_msg ON last_msg.channel_id = cc.id AND last_msg.rn = 1
                    LEFT JOIN users last_msg_user ON last_msg_user.id = last_msg.sender_id
                    LEFT JOIN (
                        SELECT cm.channel_id, COUNT(*) AS cnt
                        FROM chat_messages cm
                        WHERE cm.deleted_at IS NULL
                          AND cm.id > COALESCE(
                            (SELECT crr.last_read_message_id FROM chat_read_receipts crr
                             WHERE crr.channel_id = cm.channel_id AND crr.user_id = ?),
                            0
                          )
                        GROUP BY cm.channel_id
                    ) unread ON unread.channel_id = cc.id
                    LEFT JOIN (
                        SELECT channel_id, COUNT(*) AS cnt
                        FROM chat_channel_members
                        WHERE left_at IS NULL AND deleted_at IS NULL
                        GROUP BY channel_id
                    ) mem_count ON mem_count.channel_id = cc.id
                    WHERE cc.is_active = 1 AND cc.deleted_at IS NULL
                    ORDER BY unread_count DESC, last_msg.created_at DESC NULLS LAST
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [userId, userId])
                return rows.map { row in
                    InboxItem(
                        id: row["channel_id"] ?? 0,
                        channelName: row["channel_name"] ?? "Chat",
                        channelType: row["channel_type"] ?? "group",
                        lastMessagePreview: row["last_message"] ?? "No messages yet",
                        lastMessageDate: row["last_message_date"] as String?,
                        lastMessageBy: row["last_message_by"] as String?,
                        unreadCount: row["unread_count"] ?? 0,
                        jobId: row["job_id"] as Int64?,
                        jobName: row["job_name"] as String?,
                        memberCount: row["member_count"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get total unread message count across all channels for the current user.
    public func getTotalUnreadCount(userId: Int64) throws -> Int {
        do {
            return try db.writer.read { dbConn in
                let count = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM chat_messages cm
                    INNER JOIN chat_channel_members ccm
                        ON ccm.channel_id = cm.channel_id
                        AND ccm.user_id = ?
                        AND ccm.left_at IS NULL AND ccm.deleted_at IS NULL
                    INNER JOIN chat_channels cc
                        ON cc.id = cm.channel_id
                        AND cc.is_active = 1 AND cc.deleted_at IS NULL
                    WHERE cm.deleted_at IS NULL
                      AND cm.id > COALESCE(
                        (SELECT crr.last_read_message_id FROM chat_read_receipts crr
                         WHERE crr.channel_id = cm.channel_id AND crr.user_id = ?),
                        0
                      )
                    """, arguments: [userId, userId])
                return count ?? 0
            }
        } catch {
            if isTableNotFoundError(error) { return 0 }
            throw error
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

    /// Parse an ISO 8601 date string from SQLite.
    private func parseDate(_ string: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: string) { return d }
        fmt.formatOptions = [.withInternetDateTime]
        if let d = fmt.date(from: string) { return d }
        // SQLite datetime format: "2024-01-15 10:30:00"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.date(from: string)
    }

    // =========================================================================
    // MARK: - Attachments
    // =========================================================================

    /// A message attachment (photo, file, or entity reference).
    public struct MessageAttachment: Sendable, Identifiable {
        public let id: Int64
        public let messageId: Int64
        public let attachmentType: String  // "photo", "file", "part_ref", "po_ref", "job_ref", "jpo_ref"
        public let filePath: String?
        public let fileName: String?
        public let fileSize: Int64?
        public let mimeType: String?
        public let referenceId: Int64?
        public let referenceLabel: String?
    }

    /// A pending attachment before the message is sent.
    public struct PendingAttachment: Sendable {
        public let type: String  // "photo", "file", "part_ref", "po_ref", "job_ref", "jpo_ref"
        public let filePath: String?
        public let fileName: String?
        public let fileSize: Int64?
        public let mimeType: String?
        public let referenceId: Int64?
        public let referenceLabel: String?

        public init(type: String, filePath: String? = nil, fileName: String? = nil,
                    fileSize: Int64? = nil, mimeType: String? = nil,
                    referenceId: Int64? = nil, referenceLabel: String? = nil) {
            self.type = type
            self.filePath = filePath
            self.fileName = fileName
            self.fileSize = fileSize
            self.mimeType = mimeType
            self.referenceId = referenceId
            self.referenceLabel = referenceLabel
        }
    }

    /// Send a message with attachments. Returns the new message row ID.
    @discardableResult
    public func sendMessageWithAttachments(
        channelId: Int64,
        content: String,
        userId: Int64,
        attachments: [PendingAttachment]
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            // Insert message
            try dbConn.execute(
                sql: """
                    INSERT INTO chat_messages
                    (channel_id, sender_id, message_type, content, created_at)
                    VALUES (?, ?, 'text', ?, datetime('now'))
                    """,
                arguments: [channelId, userId, content]
            )
            let messageId = dbConn.lastInsertedRowID

            // Insert each attachment
            for att in attachments {
                try dbConn.execute(
                    sql: """
                        INSERT INTO message_attachments
                        (message_id, attachment_type, file_path, file_name, file_size,
                         mime_type, reference_id, reference_label)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [messageId, att.type, att.filePath, att.fileName,
                                att.fileSize, att.mimeType, att.referenceId, att.referenceLabel]
                )
            }

            return messageId
        }
    }

    /// Get attachments for a message.
    public func getMessageAttachments(messageId: Int64) throws -> [MessageAttachment] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT id, message_id, attachment_type, file_path, file_name,
                           file_size, mime_type, reference_id, reference_label
                    FROM message_attachments
                    WHERE message_id = ? AND deleted_at IS NULL
                    ORDER BY id ASC
                    """, arguments: [messageId])
                return rows.map { row in
                    MessageAttachment(
                        id: row["id"] ?? 0,
                        messageId: row["message_id"] ?? 0,
                        attachmentType: row["attachment_type"] ?? "file",
                        filePath: row["file_path"],
                        fileName: row["file_name"],
                        fileSize: row["file_size"],
                        mimeType: row["mime_type"],
                        referenceId: row["reference_id"],
                        referenceLabel: row["reference_label"]
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get attachments for multiple messages at once (for batch loading in thread view).
    public func getAttachmentsForMessages(messageIds: [Int64]) throws -> [Int64: [MessageAttachment]] {
        guard !messageIds.isEmpty else { return [:] }
        do {
            return try db.writer.read { dbConn in
                let placeholders = messageIds.map { _ in "?" }.joined(separator: ",")
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT id, message_id, attachment_type, file_path, file_name,
                           file_size, mime_type, reference_id, reference_label
                    FROM message_attachments
                    WHERE message_id IN (\(placeholders)) AND deleted_at IS NULL
                    ORDER BY id ASC
                    """, arguments: StatementArguments(messageIds))

                var result: [Int64: [MessageAttachment]] = [:]
                for row in rows {
                    let att = MessageAttachment(
                        id: row["id"] ?? 0,
                        messageId: row["message_id"] ?? 0,
                        attachmentType: row["attachment_type"] ?? "file",
                        filePath: row["file_path"],
                        fileName: row["file_name"],
                        fileSize: row["file_size"],
                        mimeType: row["mime_type"],
                        referenceId: row["reference_id"],
                        referenceLabel: row["reference_label"]
                    )
                    result[att.messageId, default: []].append(att)
                }
                return result
            }
        } catch {
            if isTableNotFoundError(error) { return [:] }
            throw error
        }
    }

    /// Auto-save photo/file attachments from a job-linked channel to the job's notebook.
    /// Best-effort — failures are silently ignored to not block message sending.
    public func autoSaveToJobNotebook(channelId: Int64, attachment: MessageAttachment) throws {
        try db.writer.write { dbConn in
            // Get job ID from channel
            guard let row = try Row.fetchOne(dbConn, sql: """
                SELECT job_id FROM chat_channels WHERE id = ? AND job_id IS NOT NULL AND deleted_at IS NULL
                """, arguments: [channelId]),
                  let jobId: Int64 = row["job_id"] else {
                return
            }

            // Get or create the job's notebook
            let notebookId: Int64
            if let existing = try Row.fetchOne(dbConn, sql: """
                SELECT id FROM notebooks WHERE job_id = ? AND deleted_at IS NULL LIMIT 1
                """, arguments: [jobId]) {
                notebookId = existing["id"] ?? 0
            } else {
                try dbConn.execute(sql: """
                    INSERT INTO notebooks (job_id, title, notebook_type, status, created_at, updated_at)
                    VALUES (?, 'Job Notebook', 'job', 'active', datetime('now'), datetime('now'))
                    """, arguments: [jobId])
                notebookId = dbConn.lastInsertedRowID
            }

            // Save as notebook entry
            let title = attachment.fileName ?? "Chat attachment"
            let content = attachment.filePath ?? attachment.referenceLabel ?? ""
            try dbConn.execute(sql: """
                INSERT INTO notebook_entries
                (notebook_id, entry_type, title, content, status, created_at, updated_at)
                VALUES (?, 'attachment', ?, ?, 'active', datetime('now'), datetime('now'))
                """, arguments: [notebookId, title, content])
        }
    }

    // =========================================================================
    // MARK: - Thread Info
    // =========================================================================

    /// A member of a channel for display in the thread info panel.
    public struct ChannelMemberInfo: Sendable, Identifiable {
        public let id: Int64          // membership row ID
        public let userId: Int64
        public let name: String
        public let role: String?      // "admin", "member"
    }

    /// Actions available in the thread info panel.
    public enum ThreadAction: String, CaseIterable, Identifiable, Sendable {
        case approve
        case reject
        case escalate
        case pushBack
        case markResolved
        case addPeople

        public var id: String { rawValue }
    }

    /// Full thread info for the inline expandable panel.
    public struct ThreadInfo: Sendable {
        public let channelType: String
        public let channelName: String

        // Source context
        public let sourceType: String?   // "jpo", "po", "job", "supplier", nil for general
        public let sourceId: Int64?
        public let sourceName: String?

        // Escalation (for Q&A/RFI)
        public let escalationLevel: String?  // "worker", "lead", "manager", "office"
        public let canEscalate: Bool
        public let canPushBack: Bool

        // People
        public let members: [ChannelMemberInfo]

        // Quick actions based on type
        public let availableActions: [ThreadAction]
    }

    /// Get thread info for a channel, including source context, members, and available actions.
    public func getThreadInfo(channelId: Int64) throws -> ThreadInfo? {
        do {
            return try db.writer.read { dbConn -> ThreadInfo? in
                // Get channel info
                guard let channelRow = try Row.fetchOne(dbConn, sql: """
                    SELECT cc.id, cc.name, cc.channel_type, cc.job_id,
                           j.job_name, j.job_number
                    FROM chat_channels cc
                    LEFT JOIN jobs j ON j.id = cc.job_id
                    WHERE cc.id = ? AND cc.deleted_at IS NULL
                    """, arguments: [channelId]) else {
                    return nil
                }

                let channelType: String = channelRow["channel_type"] ?? "group"
                let channelName: String = channelRow["name"] ?? channelRow["job_name"] ?? "Chat"
                let jobId: Int64? = channelRow["job_id"]
                let jobName: String? = channelRow["job_name"]

                // Determine source context
                var sourceType: String? = nil
                var sourceId: Int64? = nil
                var sourceName: String? = nil

                if channelType == "supplier" {
                    // Get supplier info from bridge
                    if let bridge = try Row.fetchOne(dbConn, sql: """
                        SELECT scb.supplier_id, s.name AS supplier_name
                        FROM supplier_channel_bridges scb
                        JOIN suppliers s ON s.id = scb.supplier_id
                        WHERE scb.channel_id = ? AND scb.deleted_at IS NULL
                        LIMIT 1
                        """, arguments: [channelId]) {
                        sourceType = "supplier"
                        sourceId = bridge["supplier_id"]
                        sourceName = bridge["supplier_name"]
                    }
                } else if channelType == "job", let jId = jobId {
                    sourceType = "job"
                    sourceId = jId
                    sourceName = jobName
                }

                // Get escalation info for Q&A/RFI channels
                var escalationLevel: String? = nil
                var canEscalate = false
                var canPushBack = false

                if channelType == "qa" || channelType == "rfi" {
                    if let qa = try Row.fetchOne(dbConn, sql: """
                        SELECT current_level, status FROM qa_threads
                        WHERE channel_id = ? AND deleted_at IS NULL
                        ORDER BY created_at DESC LIMIT 1
                        """, arguments: [channelId]) {
                        let level: String = qa["current_level"] ?? "worker"
                        let status: String = qa["status"] ?? "open"
                        escalationLevel = level
                        if status == "open" {
                            canEscalate = level != "office"
                            canPushBack = level != "worker"
                        }
                    }
                }

                // Get channel members
                let memberRows = try Row.fetchAll(dbConn, sql: """
                    SELECT ccm.id, ccm.user_id, ccm.role,
                           COALESCE(u.display_name, u.first_name || ' ' || u.last_name, u.email, 'Unknown') AS name
                    FROM chat_channel_members ccm
                    LEFT JOIN users u ON u.id = ccm.user_id
                    WHERE ccm.channel_id = ? AND ccm.left_at IS NULL AND ccm.deleted_at IS NULL
                    ORDER BY ccm.role DESC, name ASC
                    """, arguments: [channelId])

                let members = memberRows.map { row in
                    ChannelMemberInfo(
                        id: row["id"] ?? 0,
                        userId: row["user_id"] ?? 0,
                        name: row["name"] ?? "Unknown",
                        role: row["role"]
                    )
                }

                // Determine available actions
                var actions: [ThreadAction] = []
                switch channelType {
                case "dm":
                    actions = [.addPeople]
                case "job":
                    actions = [.markResolved, .addPeople]
                case "qa", "rfi":
                    if canEscalate { actions.append(.escalate) }
                    if canPushBack { actions.append(.pushBack) }
                    actions.append(.markResolved)
                    actions.append(.addPeople)
                case "supplier":
                    actions = [.addPeople]
                default:
                    actions = [.addPeople]
                }

                return ThreadInfo(
                    channelType: channelType,
                    channelName: channelName,
                    sourceType: sourceType,
                    sourceId: sourceId,
                    sourceName: sourceName,
                    escalationLevel: escalationLevel,
                    canEscalate: canEscalate,
                    canPushBack: canPushBack,
                    members: members,
                    availableActions: actions
                )
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Escalation
    // =========================================================================

    /// An escalation step in the timeline history.
    public struct EscalationStep: Sendable, Identifiable {
        public let id: Int64
        public let level: String       // "worker", "lead", "manager", "office"
        public let levelLabel: String   // "Worker", "Lead", "Manager", "Office"
        public let isCurrent: Bool
        public let isComplete: Bool
        public let reviewedBy: String?
        public let reviewedAt: Date?
        public let notes: String?
    }

    /// Get escalation history for a Q&A thread, building a step-by-step timeline.
    public func getEscalationHistory(threadId: Int64) throws -> [EscalationStep] {
        do {
            return try db.writer.read { dbConn -> [EscalationStep] in
                // Get the thread's current level
                guard let threadRow = try Row.fetchOne(dbConn, sql: """
                    SELECT current_level, status FROM qa_threads WHERE id = ? AND deleted_at IS NULL
                    """, arguments: [threadId]) else {
                    return []
                }
                let currentLevel: String = threadRow["current_level"] ?? "worker"

                // Get escalation records
                let escRows = try Row.fetchAll(dbConn, sql: """
                    SELECT qe.id, qe.from_level, qe.to_level, qe.reason, qe.created_at,
                           COALESCE(u.display_name, u.first_name || ' ' || u.last_name, u.email, 'Unknown') AS escalated_by_name
                    FROM qa_escalations qe
                    LEFT JOIN users u ON u.id = qe.escalated_by
                    WHERE qe.thread_id = ?
                    ORDER BY qe.created_at ASC
                    """, arguments: [threadId])

                // Build a map of level → escalation info
                let levelOrder = ["worker", "lead", "manager", "office"]
                let levelLabels = ["worker": "Worker", "lead": "Lead", "manager": "Manager", "office": "Office"]

                // Track which levels have been reviewed and by whom
                var levelInfo: [String: (by: String?, at: Date?, notes: String?)] = [:]
                for row in escRows {
                    let fromLevel: String = row["from_level"] ?? ""
                    let toLevel: String = row["to_level"] ?? ""
                    let name: String? = row["escalated_by_name"]
                    let dateStr: String? = row["created_at"]
                    let reason: String? = row["reason"]

                    let date = dateStr.flatMap { parseDate($0) }

                    // The fromLevel was reviewed by this person (they chose to escalate/push back)
                    levelInfo[fromLevel] = (by: name, at: date, notes: nil)
                    // If pushing back, the to_level gets the reason
                    let fromIdx = levelOrder.firstIndex(of: fromLevel) ?? 0
                    let toIdx = levelOrder.firstIndex(of: toLevel) ?? 0
                    if toIdx < fromIdx {
                        // Push back — attach reason to the target level
                        levelInfo[toLevel] = (by: nil, at: nil, notes: reason)
                    }
                }

                let currentIdx = levelOrder.firstIndex(of: currentLevel) ?? 0

                return levelOrder.enumerated().map { (idx, level) in
                    let info = levelInfo[level]
                    return EscalationStep(
                        id: Int64(idx),
                        level: level,
                        levelLabel: levelLabels[level] ?? level.capitalized,
                        isCurrent: level == currentLevel,
                        isComplete: idx < currentIdx,
                        reviewedBy: info?.by,
                        reviewedAt: info?.at,
                        notes: info?.notes
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Escalate a Q&A thread to the next level.
    public func escalateThread(threadId: Int64, escalatedBy: Int64, notes: String?) throws {
        try db.writer.write { dbConn in
            guard let row = try Row.fetchOne(dbConn, sql: """
                SELECT current_level FROM qa_threads WHERE id = ? AND deleted_at IS NULL
                """, arguments: [threadId]) else {
                return
            }
            let current: String = row["current_level"] ?? "worker"
            let levelOrder = ["worker", "lead", "manager", "office"]
            guard let idx = levelOrder.firstIndex(of: current), idx < levelOrder.count - 1 else { return }
            let nextLevel = levelOrder[idx + 1]

            // Update thread
            try dbConn.execute(sql: """
                UPDATE qa_threads SET current_level = ?, status = 'escalated', updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [nextLevel, threadId])

            // Insert escalation record
            try dbConn.execute(sql: """
                INSERT INTO qa_escalations (thread_id, from_level, to_level, escalated_by, reason, created_at)
                VALUES (?, ?, ?, ?, ?, datetime('now'))
                """, arguments: [threadId, current, nextLevel, escalatedBy, notes])
        }
    }

    /// Push a Q&A thread back down one level with feedback.
    public func pushBackThread(threadId: Int64, pushedBackBy: Int64, reason: String) throws {
        try db.writer.write { dbConn in
            guard let row = try Row.fetchOne(dbConn, sql: """
                SELECT current_level FROM qa_threads WHERE id = ? AND deleted_at IS NULL
                """, arguments: [threadId]) else {
                return
            }
            let current: String = row["current_level"] ?? "worker"
            let levelOrder = ["worker", "lead", "manager", "office"]
            guard let idx = levelOrder.firstIndex(of: current), idx > 0 else { return }
            let prevLevel = levelOrder[idx - 1]

            // Update thread
            try dbConn.execute(sql: """
                UPDATE qa_threads SET current_level = ?, status = 'open', updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [prevLevel, threadId])

            // Insert escalation record (direction is indicated by from > to)
            try dbConn.execute(sql: """
                INSERT INTO qa_escalations (thread_id, from_level, to_level, escalated_by, reason, created_at)
                VALUES (?, ?, ?, ?, ?, datetime('now'))
                """, arguments: [threadId, current, prevLevel, pushedBackBy, reason])
        }
    }

    /// Mark a Q&A thread as resolved.
    public func resolveQAThread(threadId: Int64, resolvedBy: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE qa_threads SET status = 'resolved', answered_by = ?, answered_at = datetime('now'),
                    closed_at = datetime('now'), updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [resolvedBy, threadId])
        }
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
