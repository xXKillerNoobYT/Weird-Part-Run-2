import Foundation
import GRDB

// MARK: - Certification

public struct Certification: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "certifications"
    public var id: Int64?
    public var userId: Int64
    public var certType: String
    public var certName: String
    public var issuer: String?
    public var certNumber: String?
    public var issuedDate: String?
    public var expiryDate: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, issuer, notes
        case userId = "user_id"
        case certType = "cert_type"
        case certName = "cert_name"
        case certNumber = "cert_number"
        case issuedDate = "issued_date"
        case expiryDate = "expiry_date"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - WageHistory

public struct WageHistory: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "wage_history"
    public var id: Int64?
    public var userId: Int64
    public var effectiveDate: String
    public var hourlyRate: Double
    public var reason: String?
    public var approvedBy: Int64?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, reason, notes
        case userId = "user_id"
        case effectiveDate = "effective_date"
        case hourlyRate = "hourly_rate"
        case approvedBy = "approved_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - EmployeeNote

public struct EmployeeNote: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "employee_notes"
    public var id: Int64?
    public var userId: Int64
    public var authorId: Int64
    public var noteType: String
    public var content: String
    public var isPrivate: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, content
        case userId = "user_id"
        case authorId = "author_id"
        case noteType = "note_type"
        case isPrivate = "is_private"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - UserSkill

public struct UserSkill: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "user_skills"
    public var id: Int64?
    public var userId: Int64
    public var skillName: String
    public var proficiency: String
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, proficiency, notes
        case userId = "user_id"
        case skillName = "skill_name"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - EmployeeTeam

public struct EmployeeTeam: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "employee_teams"
    public var id: Int64?
    public var name: String
    public var description: String?
    public var leadId: Int64?
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case leadId = "lead_id"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - EmployeeTeamMember

public struct EmployeeTeamMember: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "employee_team_members"
    public var id: Int64?
    public var teamId: Int64
    public var userId: Int64
    public var role: String
    public var joinedAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, role
        case teamId = "team_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - EntityContact

public struct EntityContact: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "entity_contacts"
    public var id: Int64?
    public var entityType: String
    public var entityId: Int64
    public var contactName: String
    public var contactRole: String?
    public var phone: String?
    public var email: String?
    public var isPrimary: Int
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, phone, email, notes
        case entityType = "entity_type"
        case entityId = "entity_id"
        case contactName = "contact_name"
        case contactRole = "contact_role"
        case isPrimary = "is_primary"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
