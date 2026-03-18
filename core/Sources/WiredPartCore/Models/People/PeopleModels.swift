import Foundation
import GRDB

// MARK: - Certification

public struct Certification: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "certifications"
    public var id: Int64?
    public var userId: Int64
    public var certType: String
    public var certName: String
    public var issuingAuthority: String?
    public var certNumber: String?
    public var issuedDate: String?
    public var expiryDate: String?
    public var isActive: Int
    public var notes: String?
    public var documentPath: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case userId = "user_id"
        case certType = "cert_type"
        case certName = "cert_name"
        case issuingAuthority = "issuing_authority"
        case certNumber = "cert_number"
        case issuedDate = "issued_date"
        case expiryDate = "expiry_date"
        case isActive = "is_active"
        case documentPath = "document_path"
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
    public var payRate: Double
    public var effectiveDate: String
    public var reason: String?
    public var changedBy: Int64?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, reason
        case userId = "user_id"
        case payRate = "pay_rate"
        case effectiveDate = "effective_date"
        case changedBy = "changed_by"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - EmployeeNote

public struct EmployeeNote: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "employee_notes"
    public var id: Int64?
    public var userId: Int64
    public var noteType: String
    public var title: String
    public var body: String
    public var isPrivate: Int
    public var createdBy: Int64?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, body
        case userId = "user_id"
        case noteType = "note_type"
        case isPrivate = "is_private"
        case createdBy = "created_by"
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
    public var yearsExperience: Double?
    public var verifiedBy: Int64?
    public var verifiedAt: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, proficiency
        case userId = "user_id"
        case skillName = "skill_name"
        case yearsExperience = "years_experience"
        case verifiedBy = "verified_by"
        case verifiedAt = "verified_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - EmployeeTeam

public struct EmployeeTeam: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "employee_teams"
    public var id: Int64?
    public var name: String
    public var description: String?
    public var leadUserId: Int64?
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case leadUserId = "lead_user_id"
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
    public var firstName: String
    public var lastName: String
    public var role: String
    public var phone: String
    public var email: String?
    public var isPrimary: Int
    public var notes: String?
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, phone, email, notes, role
        case entityType = "entity_type"
        case entityId = "entity_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case isPrimary = "is_primary"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
