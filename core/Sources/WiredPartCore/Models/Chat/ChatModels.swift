import Foundation
import GRDB

// MARK: - ChatChannel

public struct ChatChannel: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "chat_channels"
    public var id: Int64?
    public var channelType: String
    public var jobId: Int64?
    public var name: String?
    public var createdBy: Int64
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case channelType = "channel_type"
        case jobId = "job_id"
        case createdBy = "created_by"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ChatChannelMember

public struct ChatChannelMember: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "chat_channel_members"
    public var id: Int64?
    public var channelId: Int64
    public var userId: Int64
    public var role: String
    public var mutedUntil: String?
    public var joinedAt: String?
    public var leftAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, role
        case channelId = "channel_id"
        case userId = "user_id"
        case mutedUntil = "muted_until"
        case joinedAt = "joined_at"
        case leftAt = "left_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ChatMessage

public struct ChatMessage: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "chat_messages"
    public var id: Int64?
    public var channelId: Int64
    public var senderId: Int64
    public var messageType: String
    public var content: String
    public var parentMessageId: Int64?
    public var isEdited: Int
    public var editedAt: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, content
        case channelId = "channel_id"
        case senderId = "sender_id"
        case messageType = "message_type"
        case parentMessageId = "parent_message_id"
        case isEdited = "is_edited"
        case editedAt = "edited_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ChatMention

public struct ChatMention: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "chat_mentions"
    public var id: Int64?
    public var messageId: Int64
    public var userId: Int64
    public var readAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case messageId = "message_id"
        case userId = "user_id"
        case readAt = "read_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - QAThread

public struct QAThread: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "qa_threads"
    public var id: Int64?
    public var channelId: Int64?
    public var jobId: Int64?
    public var askedBy: Int64
    public var question: String
    public var currentLevel: String
    public var status: String
    public var priority: String
    public var answer: String?
    public var answeredBy: Int64?
    public var answeredAt: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, question, status, priority, answer
        case channelId = "channel_id"
        case jobId = "job_id"
        case askedBy = "asked_by"
        case currentLevel = "current_level"
        case answeredBy = "answered_by"
        case answeredAt = "answered_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - QAEscalation

public struct QAEscalation: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "qa_escalations"
    public var id: Int64?
    public var threadId: Int64
    public var fromLevel: String
    public var toLevel: String
    public var escalatedBy: Int64
    public var reason: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, reason
        case threadId = "thread_id"
        case fromLevel = "from_level"
        case toLevel = "to_level"
        case escalatedBy = "escalated_by"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - RFI

public struct RFI: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "rfis"
    public var id: Int64?
    public var threadId: Int64
    public var gcContactId: Int64?
    public var subject: String
    public var body: String?
    public var status: String
    public var sentAt: String?
    public var response: String?
    public var respondedAt: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, subject, body, status, response
        case threadId = "thread_id"
        case gcContactId = "gc_contact_id"
        case sentAt = "sent_at"
        case respondedAt = "responded_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
