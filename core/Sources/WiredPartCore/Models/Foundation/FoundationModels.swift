import Foundation
import GRDB

// MARK: - User

public struct User: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "users"

    public var id: Int64?
    public var displayName: String
    public var email: String?
    public var phone: String?
    public var pinHash: String?
    public var defaultTruckId: Int64?
    public var emergencyContactName: String?
    public var emergencyContactPhone: String?
    public var certification: String?
    public var hireDate: String?
    public var payRate: Double?
    public var isActive: Int
    public var avatarUrl: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email, phone
        case pinHash = "pin_hash"
        case defaultTruckId = "default_truck_id"
        case emergencyContactName = "emergency_contact_name"
        case emergencyContactPhone = "emergency_contact_phone"
        case certification
        case hireDate = "hire_date"
        case payRate = "pay_rate"
        case isActive = "is_active"
        case avatarUrl = "avatar_url"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Hat

public struct Hat: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "hats"

    public var id: Int64?
    public var name: String
    public var level: Int
    public var description: String?
    public var isBuiltin: Int
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, level, description
        case isBuiltin = "is_builtin"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - HatPermission

public struct HatPermission: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "hat_permissions"

    public var id: Int64?
    public var hatId: Int64
    public var permissionKey: String
    public var grantedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case hatId = "hat_id"
        case permissionKey = "permission_key"
        case grantedAt = "granted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - UserHat

public struct UserHat: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "user_hats"

    public var id: Int64?
    public var userId: Int64
    public var hatId: Int64
    public var isPrimary: Int
    public var grantedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case hatId = "hat_id"
        case isPrimary = "is_primary"
        case grantedAt = "granted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Device

public struct Device: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "devices"

    public var id: Int64?
    public var deviceId: String
    public var deviceName: String
    public var platform: String?
    public var appVersion: String?
    public var userId: Int64?
    public var lastSyncAt: String?
    public var isTrusted: Int
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case deviceName = "device_name"
        case platform
        case appVersion = "app_version"
        case userId = "user_id"
        case lastSyncAt = "last_sync_at"
        case isTrusted = "is_trusted"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Setting

public struct Setting: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "settings"

    public var id: Int64?
    public var key: String
    public var value: String?
    public var category: String
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, key, value, category
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Notification

public struct AppNotification: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "notifications"

    public var id: Int64?
    public var userId: Int64
    public var type: String
    public var title: String
    public var message: String?
    public var data: String?
    public var isRead: Int
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type, title, message, data
        case isRead = "is_read"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
