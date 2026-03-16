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
        public let senderName: String
        public let content: String
        public let messageType: String
        public let createdAt: String?

        public init(
            id: Int64, senderName: String, content: String,
            messageType: String, createdAt: String?
        ) {
            self.id = id
            self.senderName = senderName
            self.content = content
            self.messageType = messageType
            self.createdAt = createdAt
        }
    }

    /// A Q&A thread row enriched with user names.
    public struct QAThreadRow: Sendable, Identifiable {
        public let id: Int64
        public let question: String
        public let askedByName: String
        public let currentLevel: String
        public let status: String
        public let priority: String
        public let answer: String?
        public let answeredByName: String?

        public init(
            id: Int64, question: String, askedByName: String,
            currentLevel: String, status: String, priority: String,
            answer: String?, answeredByName: String?
        ) {
            self.id = id
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
                    SELECT cm.id, cm.content, cm.message_type, cm.created_at,
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
                    (channel_id, sender_id, message_type, content, is_edited, created_at)
                    VALUES (?, ?, 'text', ?, 0, datetime('now'))
                    """,
                arguments: [channelId, senderId, content]
            )
            return dbConn.lastInsertedRowID
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
                    SELECT qa.id, qa.question, qa.current_level, qa.status, qa.priority,
                           qa.answer,
                           COALESCE(ua.display_name, ua.email, 'Unknown') AS asked_by_name,
                           COALESCE(ub.display_name, ub.email) AS answered_by_name
                    FROM qa_threads qa
                    LEFT JOIN users ua ON ua.id = qa.asked_by
                    LEFT JOIN users ub ON ub.id = qa.answered_by
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY qa.created_at DESC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args as [Any])!)
                return rows.map { row in
                    QAThreadRow(
                        id: row["id"] ?? 0,
                        question: row["question"] ?? "",
                        askedByName: row["asked_by_name"] ?? "Unknown",
                        currentLevel: row["current_level"] ?? "field",
                        status: row["status"] ?? "open",
                        priority: row["priority"] ?? "normal",
                        answer: row["answer"] as String?,
                        answeredByName: row["answered_by_name"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
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
            sql: "SELECT COUNT(*) FROM chat_mentions WHERE read_at IS NULL"
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
}
