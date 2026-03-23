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
    public var pinSalt: String?
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
        case pinSalt = "pin_salt"
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

// MARK: - Business Profile

public struct BusinessProfile: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "business_profiles"

    public var id: Int64?
    public var companyName: String
    public var industry: String?
    public var address: String?
    public var city: String?
    public var state: String?
    public var zip: String?
    public var phone: String?
    public var email: String?
    public var website: String?
    public var logoData: Data?
    public var timezone: String?
    public var isActive: Int
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyName = "company_name"
        case industry, address, city, state, zip, phone, email, website
        case logoData = "logo_data"
        case timezone
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// ISO-8601 timestamp for "now" matching SQLite's `datetime('now')`.
    private static func now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    public init(
        id: Int64? = nil,
        companyName: String,
        industry: String? = nil,
        address: String? = nil,
        city: String? = nil,
        state: String? = nil,
        zip: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        website: String? = nil,
        logoData: Data? = nil,
        timezone: String? = "America/Chicago",
        isActive: Int = 1,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        let timestamp = Self.now()
        self.id = id
        self.companyName = companyName
        self.industry = industry
        self.address = address
        self.city = city
        self.state = state
        self.zip = zip
        self.phone = phone
        self.email = email
        self.website = website
        self.logoData = logoData
        self.timezone = timezone
        self.isActive = isActive
        self.createdAt = createdAt ?? timestamp
        self.updatedAt = updatedAt ?? timestamp
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

    enum CodingKeys: String, CodingKey {
        case id
        case hatId = "hat_id"
        case permissionKey = "permission_key"
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
    public var isActive: Int
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case hatId = "hat_id"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Device

public struct Device: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "devices"

    public var id: Int64?
    public var deviceName: String
    public var deviceFingerprint: String?
    public var assignedUserId: Int64?
    public var isPublic: Int
    public var lastSeen: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case deviceName = "device_name"
        case deviceFingerprint = "device_fingerprint"
        case assignedUserId = "assigned_user_id"
        case isPublic = "is_public"
        case lastSeen = "last_seen"
        case deletedAt = "deleted_at"
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
    public var title: String
    public var body: String?
    public var severity: String?
    public var source: String?
    public var link: String?
    public var isRead: Int
    public var type: String?
    public var message: String?
    public var entityType: String?
    public var entityId: Int64?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, body, severity, source, link, type, message
        case userId = "user_id"
        case isRead = "is_read"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
