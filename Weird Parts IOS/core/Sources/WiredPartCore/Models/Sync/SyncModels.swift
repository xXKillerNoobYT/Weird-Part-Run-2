import Foundation
import GRDB

// MARK: - ChangeLogEntry

public struct ChangeLogEntry: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "_change_log"

    public var id: Int64?
    public var deviceId: String
    public var tableName: String
    public var recordId: Int64
    public var operation: String
    public var changedFields: String?
    public var oldValues: String?
    public var timestamp: String
    public var synced: Int
    public var syncBatchId: String?
    public var sequence: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case tableName = "table_name"
        case recordId = "record_id"
        case operation
        case changedFields = "changed_fields"
        case oldValues = "old_values"
        case timestamp, synced
        case syncBatchId = "sync_batch_id"
        case sequence
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - ConflictLogEntry

public struct ConflictLogEntry: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "_conflict_log"

    public var id: Int64?
    public var tableName: String
    public var recordId: String
    public var fieldName: String
    public var localValue: String?
    public var remoteValue: String?
    public var winner: String
    public var localDevice: String
    public var remoteDevice: String
    public var localTs: String
    public var remoteTs: String
    public var resolvedAt: String?
    public var reviewed: Int = 0

    enum CodingKeys: String, CodingKey {
        case id
        case tableName = "table_name"
        case recordId = "record_id"
        case fieldName = "field_name"
        case localValue = "local_value"
        case remoteValue = "remote_value"
        case winner
        case localDevice = "local_device"
        case remoteDevice = "remote_device"
        case localTs = "local_ts"
        case remoteTs = "remote_ts"
        case resolvedAt = "resolved_at"
        case reviewed
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - VectorClockEntry

public struct VectorClockEntry: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "_vector_clock"

    public var id: Int64?
    public var deviceId: String
    public var peerId: String
    public var lastSequence: Int64
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case peerId = "peer_id"
        case lastSequence = "last_sequence"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - DeviceRegistryEntry

public struct DeviceRegistryEntry: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "_device_registry"

    public var id: Int64?
    public var deviceId: String
    public var deviceName: String
    public var platform: String?
    public var lastSeenAt: String?
    public var lastSyncAt: String?
    public var isTrusted: Int
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case deviceName = "device_name"
        case platform
        case lastSeenAt = "last_seen_at"
        case lastSyncAt = "last_sync_at"
        case isTrusted = "is_trusted"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
