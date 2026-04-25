import Foundation
import GRDB
import CryptoKit

/// People Service — read-only queries for employees, customers, contractors,
/// contacts, teams, hats, and aggregate people stats.
///
/// All queries run against the local SQLite database via GRDB.
/// Tables that may not yet exist are handled gracefully: queries that
/// hit a missing table return zero counts or empty arrays rather than throwing.
///
/// Ported from: People feature area (Phase 8, 10)
public final class PeopleService: Sendable {
    private let db: AppDatabase

    private enum EncryptionError: Error {
        case missingKey
        case invalidKey
    }

    public init(db: AppDatabase) {
        self.db = db
    }

    private func encryptionKey() throws -> SymmetricKey {
        guard let b64 = ProcessInfo.processInfo.environment["PEOPLE_DB_ENCRYPTION_KEY"],
              let keyData = Data(base64Encoded: b64) else {
            throw EncryptionError.missingKey
        }
        guard keyData.count == 32 else {
            throw EncryptionError.invalidKey
        }
        return SymmetricKey(data: keyData)
    }

    private func encryptOptional(_ value: String?) throws -> String? {
        guard let value, !value.isEmpty else { return value }
        let box = try AES.GCM.seal(Data(value.utf8), using: try encryptionKey())
        guard let combined = box.combined else { return nil }
        return combined.base64EncodedString()
    }

    // =========================================================================
    // MARK: - Error Types
    // =========================================================================

    public enum PeopleError: Error, Sendable, Equatable {
        case employeeNotFound(Int64)
        case customerNotFound(Int64)
        case contactNotFound(Int64)
        case contractorNotFound(Int64)
        case userNotFound(Int64)
        case cannotDeleteBuiltinHat
        case requiredFieldEmpty(String)
        case hatNotFound(Int64)
        case invalidScore(Double)
        case invalidAmount(Double)
    }

    // =========================================================================
    // MARK: - Result Types
    // =========================================================================

    /// An employee row for list views with hat names.
    public struct EmployeeListItem: Sendable, Identifiable {
        public let id: Int64
        public let displayName: String
        public let email: String
        public let phone: String?
        public let status: String
        public let role: String
        public let hatNames: String?

        public init(
            id: Int64, displayName: String, email: String, phone: String?,
            status: String, role: String, hatNames: String?
        ) {
            self.id = id
            self.displayName = displayName
            self.email = email
            self.phone = phone
            self.status = status
            self.role = role
            self.hatNames = hatNames
        }
    }

    /// Full employee detail with hats and team memberships.
    public struct EmployeeDetail: Sendable {
        public let id: Int64
        public let displayName: String
        public let email: String
        public let phone: String?
        public let status: String
        public let role: String
        public let createdAt: String?
        public let updatedAt: String?
        public let deletedAt: String?
        public let hats: [HatInfo]
        public let teams: [TeamMembershipInfo]
        public let certifications: [Certification]
        public let skills: [UserSkill]

        public init(
            id: Int64, displayName: String, email: String, phone: String?,
            status: String, role: String,
            createdAt: String?, updatedAt: String?, deletedAt: String?,
            hats: [HatInfo], teams: [TeamMembershipInfo],
            certifications: [Certification] = [],
            skills: [UserSkill] = []
        ) {
            self.id = id
            self.displayName = displayName
            self.email = email
            self.phone = phone
            self.status = status
            self.role = role
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
            self.hats = hats
            self.teams = teams
            self.certifications = certifications
            self.skills = skills
        }
    }

    /// A hat assigned to an employee.
    public struct HatInfo: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let description: String?

        public init(id: Int64, name: String, description: String?) {
            self.id = id
            self.name = name
            self.description = description
        }
    }

    /// A team membership for an employee.
    public struct TeamMembershipInfo: Sendable, Identifiable {
        public let id: Int64
        public let teamId: Int64
        public let teamName: String
        public let role: String
        public let joinedAt: String?

        public init(id: Int64, teamId: Int64, teamName: String, role: String, joinedAt: String?) {
            self.id = id
            self.teamId = teamId
            self.teamName = teamName
            self.role = role
            self.joinedAt = joinedAt
        }
    }

    /// A customer row for list views.
    public struct CustomerListItem: Sendable, Identifiable {
        public let id: Int64
        public let companyName: String?
        public let contactName: String?
        public let email: String?
        public let phone: String?

        public init(id: Int64, companyName: String?, contactName: String?, email: String?, phone: String?) {
            self.id = id
            self.companyName = companyName
            self.contactName = contactName
            self.email = email
            self.phone = phone
        }
    }

    /// A contractor row for list views (contacts with contact_type = 'contractor').
    public struct ContractorListItem: Sendable, Identifiable {
        public let id: Int64
        public let firstName: String
        public let lastName: String
        public let company: String?
        public let email: String?
        public let phone: String?

        public init(id: Int64, firstName: String, lastName: String, company: String?, email: String?, phone: String?) {
            self.id = id
            self.firstName = firstName
            self.lastName = lastName
            self.company = company
            self.email = email
            self.phone = phone
        }
    }

    /// A contact row for list views.
    public struct ContactListItem: Sendable, Identifiable {
        public let id: Int64
        public let firstName: String
        public let lastName: String
        public let company: String?
        public let email: String?
        public let phone: String?
        public let contactType: String?

        public init(
            id: Int64, firstName: String, lastName: String, company: String?,
            email: String?, phone: String?, contactType: String?
        ) {
            self.id = id
            self.firstName = firstName
            self.lastName = lastName
            self.company = company
            self.email = email
            self.phone = phone
            self.contactType = contactType
        }
    }

    /// A team row for list views with leader name and member count.
    public struct TeamListItem: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let description: String?
        public let leaderName: String?
        public let memberCount: Int

        public init(id: Int64, name: String, description: String?, leaderName: String?, memberCount: Int) {
            self.id = id
            self.name = name
            self.description = description
            self.leaderName = leaderName
            self.memberCount = memberCount
        }
    }

    /// A hat row for list views with user count.
    public struct HatListItem: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let description: String?
        public let userCount: Int

        public init(id: Int64, name: String, description: String?, userCount: Int) {
            self.id = id
            self.name = name
            self.description = description
            self.userCount = userCount
        }
    }

    /// A user assigned to a hat (for HatDetailSheet member list).
    public struct HatMember: Sendable, Identifiable {
        public let id: Int64
        public let displayName: String
        public let phone: String?
        public let email: String?
        public let assignedAt: String?

        public init(id: Int64, displayName: String, phone: String?, email: String?, assignedAt: String?) {
            self.id = id
            self.displayName = displayName
            self.phone = phone
            self.email = email
            self.assignedAt = assignedAt
        }
    }

    /// Aggregate people statistics.
    public struct PeopleStats: Sendable {
        public let totalEmployees: Int
        public let activeEmployees: Int
        public let totalCustomers: Int
        public let totalContacts: Int

        public init(totalEmployees: Int, activeEmployees: Int, totalCustomers: Int, totalContacts: Int) {
            self.totalEmployees = totalEmployees
            self.activeEmployees = activeEmployees
            self.totalCustomers = totalCustomers
            self.totalContacts = totalContacts
        }
    }

    // =========================================================================
    // MARK: - 1. Employees
    // =========================================================================

    /// List employees with optional search and status filter.
    /// Hat names are aggregated as a comma-separated string via GROUP_CONCAT.
    public func listEmployees(
        search: String? = nil,
        status: String? = nil
    ) throws -> [EmployeeListItem] {
        do {
            return try db.writer.read { dbConn -> [EmployeeListItem] in
                var whereClauses = ["u.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("(u.display_name LIKE ? OR u.email LIKE ? OR u.phone LIKE ?)")
                    let pattern = "%\(search)%"
                    args.append(pattern)
                    args.append(pattern)
                    args.append(pattern)
                }
                if let status, !status.isEmpty {
                    if status == "active" {
                        whereClauses.append("u.is_active = 1")
                    } else if status == "inactive" {
                        whereClauses.append("u.is_active = 0")
                    }
                }

                let sql = """
                    SELECT u.id, u.display_name, u.email, u.phone,
                           CASE WHEN u.is_active = 1 THEN 'active' ELSE 'inactive' END AS status,
                           COALESCE(MAX(h.name), 'user') AS role,
                           GROUP_CONCAT(h.name, ', ') AS hat_names
                    FROM users u
                    LEFT JOIN user_hats uh ON uh.user_id = u.id AND uh.deleted_at IS NULL
                    LEFT JOIN hats h ON h.id = uh.hat_id
                    WHERE \(whereClauses.joined(separator: " AND "))
                    GROUP BY u.id
                    ORDER BY u.display_name ASC, u.email ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    EmployeeListItem(
                        id: row["id"] ?? 0,
                        displayName: row["display_name"] ?? row["email"] ?? "Unknown",
                        email: row["email"] ?? "",
                        phone: row["phone"] as String?,
                        status: row["status"] ?? "active",
                        role: row["role"] ?? "user",
                        hatNames: row["hat_names"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get full employee detail by ID, including hats and team memberships.
    public func getEmployeeDetail(id: Int64) throws -> EmployeeDetail {
        let result: EmployeeDetail? = try db.writer.read { dbConn -> EmployeeDetail? in
            // Fetch user row
            guard let userRow = try Row.fetchOne(
                dbConn,
                sql: """
                    SELECT id, display_name, email, phone,
                           CASE WHEN is_active = 1 THEN 'active' ELSE 'inactive' END AS status,
                           created_at, updated_at, deleted_at
                    FROM users
                    WHERE id = ?
                    """,
                arguments: [id]
            ) else {
                return nil
            }

            // Fetch hats for this user
            var hats: [HatInfo] = []
            do {
                let hatRows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT h.id, h.name, h.description
                        FROM hats h
                        JOIN user_hats uh ON uh.hat_id = h.id
                        WHERE uh.user_id = ? AND uh.deleted_at IS NULL
                        ORDER BY h.name ASC
                        """,
                    arguments: [id]
                )
                hats = hatRows.map { row in
                    HatInfo(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        description: row["description"] as String?
                    )
                }
            } catch {
                // If hats/user_hats tables don't exist yet, leave empty
                if !isTableNotFoundError(error) { throw error }
            }

            // Fetch team memberships for this user
            var teams: [TeamMembershipInfo] = []
            do {
                let teamRows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT tm.id, tm.team_id, t.name AS team_name, tm.role, tm.joined_at
                        FROM employee_team_members tm
                        JOIN employee_teams t ON t.id = tm.team_id AND t.deleted_at IS NULL
                        WHERE tm.user_id = ? AND tm.deleted_at IS NULL
                        ORDER BY t.name ASC
                        """,
                    arguments: [id]
                )
                teams = teamRows.map { row in
                    TeamMembershipInfo(
                        id: row["id"] ?? 0,
                        teamId: row["team_id"] ?? 0,
                        teamName: row["team_name"] ?? "",
                        role: row["role"] ?? "member",
                        joinedAt: row["joined_at"] as String?
                    )
                }
            } catch {
                if !isTableNotFoundError(error) { throw error }
            }

            // Fetch certifications for this user
            var certifications: [Certification] = []
            do {
                certifications = try Certification
                    .filter(Column("user_id") == id)
                    .filter(Column("deleted_at") == nil)
                    .filter(Column("is_active") == 1)
                    .order(Column("expiry_date").asc)
                    .fetchAll(dbConn)
            } catch {
                if !isTableNotFoundError(error) { throw error }
            }

            // Fetch skills for this user
            var skills: [UserSkill] = []
            do {
                skills = try UserSkill
                    .filter(Column("user_id") == id)
                    .filter(Column("deleted_at") == nil)
                    .order(Column("skill_name").asc)
                    .fetchAll(dbConn)
            } catch {
                if !isTableNotFoundError(error) { throw error }
            }

            return EmployeeDetail(
                id: userRow["id"] ?? 0,
                displayName: userRow["display_name"] ?? userRow["email"] ?? "Unknown",
                email: userRow["email"] ?? "",
                phone: userRow["phone"] as String?,
                status: userRow["status"] ?? "active",
                role: hats.first?.name ?? "user",
                createdAt: userRow["created_at"] as String?,
                updatedAt: userRow["updated_at"] as String?,
                deletedAt: userRow["deleted_at"] as String?,
                hats: hats,
                teams: teams,
                certifications: certifications,
                skills: skills
            )
        }
        guard let result else { throw PeopleError.employeeNotFound(id) }
        return result
    }

    /// Fetch active certifications for a specific employee.
    public func getEmployeeCertifications(userId: Int64) throws -> [Certification] {
        do {
            return try db.writer.read { dbConn in
                try Certification
                    .filter(Column("user_id") == userId)
                    .filter(Column("deleted_at") == nil)
                    .filter(Column("is_active") == 1)
                    .order(Column("expiry_date").asc)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Add a certification to an employee.
    public func addCertification(
        userId: Int64,
        certType: String,
        certName: String,
        issuingAuthority: String? = nil,
        certNumber: String? = nil,
        issuedDate: String? = nil,
        expiryDate: String? = nil,
        notes: String? = nil
    ) throws -> Certification {
        guard !certType.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("certType")
        }
        guard !certName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("certName")
        }
        try db.writer.read { dbConn in
            guard try Row.fetchOne(dbConn, sql: "SELECT id FROM users WHERE id = ? AND deleted_at IS NULL", arguments: [userId]) != nil else {
                throw PeopleError.employeeNotFound(userId)
            }
        }
        return try db.writer.write { dbConn in
            var cert = Certification(
                id: nil, userId: userId, certType: certType, certName: certName,
                issuingAuthority: issuingAuthority, certNumber: certNumber,
                issuedDate: issuedDate, expiryDate: expiryDate, isActive: 1,
                notes: notes, documentPath: nil, deletedAt: nil,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            try cert.insert(dbConn)
            return cert
        }
    }

    /// Soft-delete a certification.
    public func removeCertification(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE certifications SET deleted_at = datetime('now'), is_active = 0 WHERE id = ? AND deleted_at IS NULL",
                arguments: [id]
            )
        }
    }

    /// Fetch skills for a specific employee.
    public func getEmployeeSkills(userId: Int64) throws -> [UserSkill] {
        do {
            return try db.writer.read { dbConn in
                try UserSkill
                    .filter(Column("user_id") == userId)
                    .filter(Column("deleted_at") == nil)
                    .order(Column("skill_name").asc)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Add a skill to an employee.
    public func addSkill(
        userId: Int64,
        skillName: String,
        proficiency: String,
        yearsExperience: Double? = nil,
        verifiedBy: Int64? = nil
    ) throws -> UserSkill {
        guard !skillName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("skillName")
        }
        guard !proficiency.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("proficiency")
        }
        try db.writer.read { dbConn in
            guard try Row.fetchOne(dbConn, sql: "SELECT id FROM users WHERE id = ? AND deleted_at IS NULL", arguments: [userId]) != nil else {
                throw PeopleError.employeeNotFound(userId)
            }
        }
        return try db.writer.write { dbConn in
            var skill = UserSkill(
                id: nil, userId: userId, skillName: skillName, proficiency: proficiency,
                yearsExperience: yearsExperience, verifiedBy: verifiedBy,
                verifiedAt: verifiedBy != nil ? ISO8601DateFormatter().string(from: Date()) : nil,
                deletedAt: nil,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
            try skill.insert(dbConn)
            return skill
        }
    }

    /// Soft-delete a skill.
    public func removeSkill(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE user_skills SET deleted_at = datetime('now') WHERE id = ? AND deleted_at IS NULL",
                arguments: [id]
            )
        }
    }

    // =========================================================================
    // MARK: - 2. Customers
    // =========================================================================

    /// List customers with optional search filter.
    /// Joins to users table for contact name via user_id.
    public func listCustomers(search: String? = nil) throws -> [CustomerListItem] {
        do {
            return try db.writer.read { dbConn -> [CustomerListItem] in
                var whereClauses = ["c.deleted_at IS NULL", "c.is_active = 1"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("(c.company_name LIKE ? OR c.name LIKE ? OR c.email LIKE ?)")
                    let pattern = "%\(search)%"
                    args.append(pattern)
                    args.append(pattern)
                    args.append(pattern)
                }

                let sql = """
                    SELECT c.id, c.company_name,
                           c.name AS contact_name,
                           c.email, c.phone
                    FROM customers c
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY COALESCE(c.company_name, c.name) ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    CustomerListItem(
                        id: row["id"] ?? 0,
                        companyName: row["company_name"] as String?,
                        contactName: row["contact_name"] as String?,
                        email: row["email"] as String?,
                        phone: row["phone"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 3. Contractors
    // =========================================================================

    /// List contractors (general_contractors table) with optional search.
    public func listContractors(search: String? = nil) throws -> [ContractorListItem] {
        do {
            return try db.writer.read { dbConn -> [ContractorListItem] in
                var whereClauses = ["gc.deleted_at IS NULL", "gc.is_active = 1"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("(gc.company_name LIKE ? OR gc.contact_name LIKE ? OR gc.email LIKE ?)")
                    let pattern = "%\(search)%"
                    args.append(pattern)
                    args.append(pattern)
                    args.append(pattern)
                }

                let sql = """
                    SELECT gc.id, gc.contact_name, gc.company_name, gc.email, gc.phone
                    FROM general_contractors gc
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY gc.company_name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    let contactName = (row["contact_name"] as String?) ?? ""
                    let parts = contactName.split(separator: " ", maxSplits: 1)
                    return ContractorListItem(
                        id: row["id"] ?? 0,
                        firstName: parts.first.map(String.init) ?? contactName,
                        lastName: parts.count > 1 ? String(parts[1]) : "",
                        company: row["company_name"] as String?,
                        email: row["email"] as String?,
                        phone: row["phone"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 4. Contacts
    // =========================================================================

    /// List all entity contacts with optional search and entity type filter.
    public func listContacts(
        search: String? = nil,
        contactType: String? = nil
    ) throws -> [ContactListItem] {
        do {
            return try db.writer.read { dbConn -> [ContactListItem] in
                var whereClauses = ["co.deleted_at IS NULL", "co.is_active = 1"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("(co.first_name LIKE ? OR co.last_name LIKE ? OR co.role LIKE ? OR co.email LIKE ?)")
                    let pattern = "%\(search)%"
                    args.append(pattern)
                    args.append(pattern)
                    args.append(pattern)
                    args.append(pattern)
                }
                if let contactType, !contactType.isEmpty {
                    whereClauses.append("co.entity_type = ?")
                    args.append(contactType)
                }

                let sql = """
                    SELECT co.id, co.first_name, co.last_name, co.role,
                           co.email, co.phone, co.entity_type
                    FROM entity_contacts co
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY co.last_name ASC, co.first_name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    ContactListItem(
                        id: row["id"] ?? 0,
                        firstName: row["first_name"] ?? "",
                        lastName: row["last_name"] ?? "",
                        company: row["role"] as String?,
                        email: row["email"] as String?,
                        phone: row["phone"] as String?,
                        contactType: row["entity_type"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 5. Teams
    // =========================================================================

    /// List all teams with leader name and member count.
    public func listTeams() throws -> [TeamListItem] {
        do {
            return try db.writer.read { dbConn -> [TeamListItem] in
                let sql = """
                    SELECT t.id, t.name, t.description,
                           COALESCE(u.display_name, u.email) AS leader_name,
                           COALESCE((SELECT COUNT(*) FROM employee_team_members tm
                                     WHERE tm.team_id = t.id AND tm.deleted_at IS NULL), 0) AS member_count
                    FROM employee_teams t
                    LEFT JOIN users u ON u.id = t.lead_user_id AND u.deleted_at IS NULL
                    WHERE t.deleted_at IS NULL AND t.is_active = 1
                    ORDER BY t.name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql)
                return rows.map { row in
                    TeamListItem(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        description: row["description"] as String?,
                        leaderName: row["leader_name"] as String?,
                        memberCount: row["member_count"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 6. Hats
    // =========================================================================

    /// List all hats with user count.
    public func listHats() throws -> [HatListItem] {
        do {
            return try db.writer.read { dbConn -> [HatListItem] in
                let sql = """
                    SELECT h.id, h.name, h.description,
                           COALESCE((SELECT COUNT(*) FROM user_hats uh
                                     WHERE uh.hat_id = h.id AND uh.deleted_at IS NULL), 0) AS user_count
                    FROM hats h
                    ORDER BY h.name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql)
                return rows.map { row in
                    HatListItem(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        description: row["description"] as String?,
                        userCount: row["user_count"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Fetch all active users assigned to a given hat (for the HatDetailSheet member list).
    ///
    /// - Parameter hatId: The hat to look up.
    /// - Returns: Users with an active (non-soft-deleted) assignment for this hat, sorted by name.
    public func getHatMembers(hatId: Int64) throws -> [HatMember] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT u.id, u.display_name, u.phone, u.email, NULL AS assigned_at
                    FROM user_hats uh
                    JOIN users u ON u.id = uh.user_id
                    WHERE uh.hat_id = ?
                      AND uh.deleted_at IS NULL
                      AND u.deleted_at IS NULL
                      AND u.is_active = 1
                    ORDER BY u.display_name ASC
                    """, arguments: [hatId])
                return rows.map { row in
                    HatMember(
                        id: row["id"] ?? 0,
                        displayName: row["display_name"] ?? "",
                        phone: row["phone"] as String?,
                        email: row["email"] as String?,
                        assignedAt: row["assigned_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 7. People Stats
    // =========================================================================

    /// Get aggregate people statistics: total/active employees, customers, contacts.
    public func getPeopleStats() throws -> PeopleStats {
        let totalEmployees = try safeCount(
            sql: "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL"
        )
        let activeEmployees = try safeCount(
            sql: "SELECT COUNT(*) FROM users WHERE is_active = 1 AND deleted_at IS NULL"
        )
        let totalCustomers = try safeCount(
            sql: "SELECT COUNT(*) FROM customers WHERE deleted_at IS NULL AND is_active = 1"
        )
        let totalContacts = try safeCount(
            sql: "SELECT COUNT(*) FROM entity_contacts WHERE deleted_at IS NULL AND is_active = 1"
        )
        return PeopleStats(
            totalEmployees: totalEmployees,
            activeEmployees: activeEmployees,
            totalCustomers: totalCustomers,
            totalContacts: totalContacts
        )
    }

    // =========================================================================
    // MARK: - 8. CRUD — Create Methods
    // =========================================================================

    /// Create a new customer. Returns the new customer's ID.
    @discardableResult
    public func createCustomer(
        name: String,
        companyName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        address: String? = nil,
        city: String? = nil,
        state: String? = nil,
        zip: String? = nil,
        notes: String? = nil
    ) throws -> Int64 {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("name")
        }
        return try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO customers (name, company_name, email, phone, address, city, state, zip, notes)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [name, companyName, email, phone, address, city, state, zip, notes]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Create a new contact (used for contractors, GC contacts, supplier contacts, etc.).
    /// Returns the new contact's ID.
    @discardableResult
    public func createContact(
        entityType: String,
        entityId: Int64,
        firstName: String,
        lastName: String = "",
        role: String,
        phone: String,
        email: String? = nil,
        isPrimary: Bool = false,
        notes: String? = nil
    ) throws -> Int64 {
        guard !entityType.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("entityType")
        }
        guard !firstName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("firstName")
        }
        let encryptedEmail = try encryptOptional(email)
        return try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO entity_contacts (entity_type, entity_id, first_name, last_name, role, phone, email, is_primary, notes)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [entityType, entityId, firstName, lastName, role, phone, encryptedEmail, isPrimary ? 1 : 0, notes]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Update an existing entity contact's basic info.
    public func updateContact(
        id: Int64,
        firstName: String,
        lastName: String,
        phone: String,
        email: String? = nil,
        role: String? = nil
    ) throws {
        guard !firstName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("firstName")
        }
        let encryptedEmail = try encryptOptional(email)
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE entity_contacts
                    SET first_name = ?, last_name = ?, phone = ?, email = ?, role = ?,
                        updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [firstName, lastName, phone, encryptedEmail, role, id]
            )
        }
    }

    /// Create a new general contractor. Returns the new contractor's ID.
    @discardableResult
    public func createContractor(
        companyName: String,
        contactName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        trade: String? = nil,
        notes: String? = nil
    ) throws -> Int64 {
        guard !companyName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("companyName")
        }
        return try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO general_contractors (company_name, contact_name, email, phone, notes)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [companyName, contactName, email, phone, notes]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Create a new team. Returns the new team's ID.
    @discardableResult
    public func createTeam(name: String, description: String? = nil) throws -> Int64 {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("name")
        }
        return try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO employee_teams (name, description)
                    VALUES (?, ?)
                    """,
                arguments: [name, description]
            )
            return dbConn.lastInsertedRowID
        }
    }

    // MARK: - Team Detail + Member Management

    /// Team detail info (lightweight).
    public struct TeamDetail: Sendable {
        public let id: Int64
        public let name: String
        public let description: String?
        public let leaderName: String?
        public let isActive: Bool
        public let createdAt: String?
    }

    /// A team member with their last work date.
    public struct TeamMemberDetail: Sendable, Identifiable {
        public let id: Int64          // user id
        public let membershipId: Int64 // employee_team_members.id
        public let name: String
        public let role: String
        public let lastWorkDate: Date?
    }

    /// A lightweight job summary for team assignments.
    public struct TeamJobSummary: Sendable, Identifiable {
        public let id: Int64
        public let jobName: String
        public let jobNumber: String
        public let status: String
    }

    /// Get team detail by ID.
    public func getTeamDetail(teamId: Int64) throws -> TeamDetail? {
        try db.writer.read { dbConn in
            guard let row = try Row.fetchOne(dbConn, sql: """
                SELECT t.id, t.name, t.description, t.is_active, t.created_at,
                       COALESCE(u.display_name, u.email) AS leader_name
                FROM employee_teams t
                LEFT JOIN users u ON u.id = t.lead_user_id AND u.deleted_at IS NULL
                WHERE t.id = ? AND t.deleted_at IS NULL
                """, arguments: [teamId]) else { return nil }

            return TeamDetail(
                id: row["id"] ?? 0,
                name: row["name"] ?? "",
                description: row["description"] as String?,
                leaderName: row["leader_name"] as String?,
                isActive: (row["is_active"] as Int? ?? 1) == 1,
                createdAt: row["created_at"] as String?
            )
        }
    }

    /// Get team members with their most recent clock entry date.
    public func getTeamMembers(teamId: Int64) throws -> [TeamMemberDetail] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT tm.id AS membership_id, u.id AS user_id,
                           COALESCE(u.display_name, u.email, 'Unknown') AS name,
                           tm.role,
                           (SELECT MAX(le.clock_in) FROM labor_entries le
                            WHERE le.user_id = u.id AND le.deleted_at IS NULL) AS last_work
                    FROM employee_team_members tm
                    JOIN users u ON u.id = tm.user_id AND u.deleted_at IS NULL
                    WHERE tm.team_id = ? AND tm.deleted_at IS NULL
                    ORDER BY u.display_name ASC
                    """, arguments: [teamId])

                return rows.map { row in
                    let lastWorkStr: String? = row["last_work"] as String?
                    let lastWork: Date? = lastWorkStr.flatMap {
                        CoreFormatters.parseISO($0)
                    }
                    return TeamMemberDetail(
                        id: row["user_id"] ?? 0,
                        membershipId: row["membership_id"] ?? 0,
                        name: row["name"] ?? "Unknown",
                        role: row["role"] ?? "member",
                        lastWorkDate: lastWork
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get jobs that members of this team are assigned to.
    public func getTeamJobs(teamId: Int64) throws -> [TeamJobSummary] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT DISTINCT j.id, j.job_name, j.job_number, j.status
                    FROM job_team_members jtm
                    JOIN employee_team_members etm ON etm.user_id = jtm.user_id AND etm.deleted_at IS NULL
                    JOIN jobs j ON j.id = jtm.job_id AND j.deleted_at IS NULL
                    WHERE etm.team_id = ?
                      AND jtm.deleted_at IS NULL
                      AND j.status IN ('active', 'in_progress', 'pending')
                    ORDER BY j.job_name ASC
                    """, arguments: [teamId])

                return rows.map { row in
                    TeamJobSummary(
                        id: row["id"] ?? 0,
                        jobName: row["job_name"] ?? "",
                        jobNumber: row["job_number"] ?? "",
                        status: row["status"] ?? "active"
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Add a user to a team.
    public func addTeamMember(teamId: Int64, userId: Int64, role: String = "member") throws {
        try db.writer.write { dbConn in
            // Guard: team + user must exist and not be tombstoned — a stale UI could
            // otherwise create orphan employee_team_members rows against deleted teams
            // or deleted users, which would be invisible to getTeamMembers (deleted_at
            // guard on JOIN users) but still polluting the INSERT OR IGNORE dedupe.
            let teamExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM employee_teams WHERE id = ? AND deleted_at IS NULL
                """, arguments: [teamId]) ?? 0) > 0
            guard teamExists else { return }
            let userExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM users WHERE id = ? AND deleted_at IS NULL AND is_active = 1
                """, arguments: [userId]) ?? 0) > 0
            guard userExists else { throw PeopleError.employeeNotFound(userId) }

            try dbConn.execute(
                sql: """
                    INSERT OR IGNORE INTO employee_team_members (team_id, user_id, role)
                    VALUES (?, ?, ?)
                    """,
                arguments: [teamId, userId, role]
            )
        }
    }

    /// Remove a user from a team (soft delete).
    public func removeTeamMember(membershipId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE employee_team_members SET deleted_at = datetime('now')
                    WHERE id = ?
                    """,
                arguments: [membershipId]
            )
        }
    }

    /// Update team name and description.
    public func updateTeam(teamId: Int64, name: String, description: String?) throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("name")
        }
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE employee_teams SET name = ?, description = ?, updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [name, description, teamId]
            )
        }
    }

    /// Soft-delete a team.
    public func deleteTeam(teamId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE employee_teams SET deleted_at = datetime('now'), updated_at = datetime('now')
                    WHERE id = ?
                    """,
                arguments: [teamId]
            )
        }
    }

    /// Get employees not already on a given team (for the add-member picker).
    public func getAvailableEmployeesForTeam(teamId: Int64) throws -> [EmployeeListItem] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT u.id, COALESCE(u.display_name, u.email) AS display_name,
                           u.email, u.phone, u.is_active,
                           CASE WHEN u.is_active = 1 THEN 'active' ELSE 'inactive' END AS status
                    FROM users u
                    WHERE u.is_active = 1 AND u.deleted_at IS NULL
                      AND u.id NOT IN (
                        SELECT tm.user_id FROM employee_team_members tm
                        WHERE tm.team_id = ? AND tm.deleted_at IS NULL
                      )
                    ORDER BY u.display_name ASC
                    """, arguments: [teamId])

                return rows.map { row in
                    EmployeeListItem(
                        id: row["id"] ?? 0,
                        displayName: row["display_name"] ?? "",
                        email: row["email"] ?? "",
                        phone: row["phone"] as String?,
                        status: row["status"] ?? "active",
                        role: "user",
                        hatNames: nil
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Create a new hat (role). Returns the new hat's ID.
    @discardableResult
    public func createHat(name: String, description: String? = nil, level: Int = 0) throws -> Int64 {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("name")
        }
        return try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO hats (name, description, level, is_builtin)
                    VALUES (?, ?, ?, 0)
                    """,
                arguments: [name, description, level]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Delete a hat by ID. Protects built-in hats from deletion (fixes #199).
    public func deleteHat(id: Int64) throws {
        try db.writer.write { dbConn in
            let isBuiltin = try Int.fetchOne(
                dbConn,
                sql: "SELECT COALESCE(is_builtin, 0) FROM hats WHERE id = ?",
                arguments: [id]
            ) ?? 0
            guard isBuiltin == 0 else {
                throw PeopleError.cannotDeleteBuiltinHat
            }
            try dbConn.execute(
                sql: "DELETE FROM hats WHERE id = ? AND is_builtin = 0",
                arguments: [id]
            )
        }
    }

    // =========================================================================
    // MARK: - Employee Edit Operations
    // =========================================================================

    /// Update employee contact details.
    public func updateEmployeeContact(
        employeeId: Int64,
        displayName: String?,
        phone: String?,
        email: String?
    ) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE users SET display_name = ?, email = ?, phone = ?, updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [displayName, email, phone, employeeId]
            )
        }
    }

    /// Get all hats with assignment status for a given employee.
    public func getAllHatsWithAssignment(employeeId: Int64) throws -> [(hat: HatInfo, isAssigned: Bool)] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT h.id, h.name, h.description,
                       CASE WHEN uh.id IS NOT NULL THEN 1 ELSE 0 END as is_assigned
                FROM hats h
                LEFT JOIN user_hats uh ON uh.hat_id = h.id AND uh.user_id = ? AND uh.deleted_at IS NULL
                ORDER BY h.name ASC
                """, arguments: [employeeId])

            return rows.map { row in
                let hat = HatInfo(
                    id: row["id"] ?? 0,
                    name: row["name"] ?? "",
                    description: row["description"] as String?
                )
                let assigned: Int = row["is_assigned"] ?? 0
                return (hat: hat, isAssigned: assigned != 0)
            }
        }
    }

    /// Toggle a hat assignment for an employee. Guards FK existence on both user + hat.
    public func toggleHatAssignment(employeeId: Int64, hatId: Int64, assign: Bool) throws {
        try db.writer.write { dbConn in
            // Guard: employee + hat must exist. Without this pre-check a stale People
            // UI with a tombstoned user id could mint orphan user_hats rows; the
            // permission engine would then refuse every action from that user because
            // the hat lookup via `user_hats JOIN users ON users.deleted_at IS NULL`
            // would return no rows, leaving the UI puzzled about "assigned but inactive".
            let employeeExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM users WHERE id = ? AND deleted_at IS NULL AND is_active = 1
                """, arguments: [employeeId]) ?? 0) > 0
            guard employeeExists else { throw PeopleError.employeeNotFound(employeeId) }
            // `hats` is hard-delete only (no deleted_at), so existence is sufficient.
            let hatExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM hats WHERE id = ?
                """, arguments: [hatId]) ?? 0) > 0
            guard hatExists else { throw PeopleError.hatNotFound(hatId) }

            if assign {
                // Check if exists (including soft-deleted)
                let existing = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM user_hats WHERE user_id = ? AND hat_id = ?
                    """, arguments: [employeeId, hatId]) ?? 0

                if existing > 0 {
                    try dbConn.execute(
                        sql: "UPDATE user_hats SET deleted_at = NULL WHERE user_id = ? AND hat_id = ?",
                        arguments: [employeeId, hatId]
                    )
                } else {
                    try dbConn.execute(
                        sql: "INSERT INTO user_hats (user_id, hat_id) VALUES (?, ?)",
                        arguments: [employeeId, hatId]
                    )
                }
            } else {
                try dbConn.execute(
                    sql: "UPDATE user_hats SET deleted_at = datetime('now') WHERE user_id = ? AND hat_id = ?",
                    arguments: [employeeId, hatId]
                )
            }
        }
    }

    // =========================================================================
    // MARK: - Dashboard Data Types
    // =========================================================================

    /// Worker currently clocked in.
    public struct WorkerStatus: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let jobName: String?
        public let clockInTime: Date
        public let currentTodo: String?

        public var elapsedTime: String {
            let elapsed = Date().timeIntervalSince(clockInTime)
            let hours = Int(elapsed) / 3600
            let minutes = (Int(elapsed) % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }

    /// Employee summary for off-today list.
    public struct EmployeeSummary: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let offReason: String?
    }

    /// Certification expiring soon.
    public struct CertificationAlert: Sendable, Identifiable {
        public let id: Int64
        public let employeeName: String
        public let certName: String
        public let expiryDate: Date

        public var daysUntilExpiry: Int {
            Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
        }
    }

    /// Team assignment for today.
    public struct TeamAssignment: Sendable, Identifiable {
        public let id: Int64
        public let teamName: String
        public let jobName: String
        public let memberCount: Int
    }

    // =========================================================================
    // MARK: - Dashboard Queries
    // =========================================================================

    /// Get all workers currently clocked in (active labor entries with no clock_out).
    public func getWorkersCurrentlyClocked() throws -> [WorkerStatus] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT le.id, le.user_id,
                           COALESCE(u.display_name, u.email, 'Unknown') as name,
                           COALESCE(j.job_name, 'Shop') as job_name,
                           le.clock_in,
                           ne.title as current_todo
                    FROM labor_entries le
                    LEFT JOIN users u ON u.id = le.user_id AND u.deleted_at IS NULL
                    LEFT JOIN jobs j ON j.id = le.job_id AND j.deleted_at IS NULL
                    LEFT JOIN notebook_entries ne ON ne.id = le.linked_todo_id AND ne.deleted_at IS NULL
                    WHERE le.clock_out IS NULL
                      AND le.deleted_at IS NULL
                    ORDER BY le.clock_in ASC
                    """)

                return rows.compactMap { row -> WorkerStatus? in
                    let userId: Int64 = row["user_id"] ?? 0
                    let clockInStr: String = row["clock_in"] ?? ""
                    guard let clockIn = CoreFormatters.parseDateTime(clockInStr) else {
                        return nil
                    }
                    return WorkerStatus(
                        id: userId,
                        name: row["name"] ?? "Unknown",
                        jobName: row["job_name"] as String?,
                        clockInTime: clockIn,
                        currentTodo: row["current_todo"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get employees who are off today (from schedule_exceptions).
    public func getEmployeesOffToday() throws -> [EmployeeSummary] {
        let today = formatDateYMD(Date())
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT se.id, se.user_id,
                           COALESCE(u.display_name, u.email, 'Unknown') as name,
                           se.exception_type as off_reason
                    FROM schedule_exceptions se
                    LEFT JOIN users u ON u.id = se.user_id AND u.deleted_at IS NULL
                    WHERE se.is_approved = 1
                      AND se.exception_date = ?
                      AND se.exception_type = 'time_off'
                      AND se.deleted_at IS NULL
                    ORDER BY u.display_name ASC
                    """, arguments: [today])

                return rows.map { row in
                    EmployeeSummary(
                        id: row["user_id"] ?? 0,
                        name: row["name"] ?? "Unknown",
                        offReason: row["off_reason"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get certifications expiring within a given number of days.
    public func getExpiringCertifications(withinDays: Int = 30) throws -> [CertificationAlert] {
        let today = Date()
        let futureDate = Calendar.current.date(byAdding: .day, value: withinDays, to: today) ?? today.addingTimeInterval(Double(withinDays) * 86400)
        let todayStr = formatDateYMD(today)
        let futureStr = formatDateYMD(futureDate)

        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT ec.id,
                           COALESCE(u.display_name, 'Unknown') as employee_name,
                           ec.cert_name,
                           ec.expiry_date
                    FROM certifications ec
                    LEFT JOIN users u ON u.id = ec.user_id AND u.deleted_at IS NULL
                    WHERE ec.expiry_date >= ? AND ec.expiry_date <= ?
                      AND ec.deleted_at IS NULL
                    ORDER BY ec.expiry_date ASC
                    """, arguments: [todayStr, futureStr])

                return rows.compactMap { row -> CertificationAlert? in
                    let expiryStr: String = row["expiry_date"] ?? ""
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd"
                    guard let expiryDate = f.date(from: expiryStr) else { return nil }
                    return CertificationAlert(
                        id: row["id"] ?? 0,
                        employeeName: row["employee_name"] ?? "Unknown",
                        certName: row["cert_name"] ?? "Unknown",
                        expiryDate: expiryDate
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get today's team assignments from the schedule.
    public func getTodaysTeamAssignments() throws -> [TeamAssignment] {
        let today = formatDateYMD(Date())

        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT et.id, et.name as team_name,
                           COALESCE(j.job_name, 'Unassigned') as job_name,
                           (SELECT COUNT(*) FROM employee_team_members etm WHERE etm.team_id = et.id AND etm.deleted_at IS NULL) as member_count
                    FROM employee_teams et
                    LEFT JOIN job_dispatch jd ON jd.dispatch_date = ? AND jd.deleted_at IS NULL
                    LEFT JOIN jobs j ON j.id = jd.job_id AND j.deleted_at IS NULL
                    WHERE et.is_active = 1 AND et.deleted_at IS NULL
                    GROUP BY et.id
                    ORDER BY et.name ASC
                    """, arguments: [today])

                return rows.map { row in
                    TeamAssignment(
                        id: row["id"] ?? 0,
                        teamName: row["team_name"] ?? "Unknown Team",
                        jobName: row["job_name"] ?? "Unassigned",
                        memberCount: row["member_count"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Customer Detail (44C)
    // =========================================================================

    /// Full customer detail with contacts, job history, stats, and communication log.
    public struct CustomerDetail: Sendable {
        public let customerId: Int64
        public let companyName: String?
        public let contactName: String?
        public let email: String?
        public let phone: String?
        public let address: String?
        public let customerType: String?
        public let contacts: [CustomerContact]
        public let jobHistory: [CustomerJobSummary]
        public let stats: CustomerStats
        public let communicationLog: [CommunicationEntry]
    }

    public struct CustomerContact: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let role: String?
        public let phone: String?
        public let email: String?
    }

    public struct CustomerJobSummary: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let jobNumber: String
        public let status: String
        public let startDate: String?
    }

    public struct CustomerStats: Sendable {
        public let totalJobs: Int
        public let activeJobs: Int
        public let completedJobs: Int
        public let totalRevenue: Double?
        public let averageJobSize: Double?
        public let firstJobDate: String?
        public let lastJobDate: String?
    }

    public struct CommunicationEntry: Sendable, Identifiable {
        public let id: Int64
        public let commType: String
        public let content: String
        public let createdBy: String
        public let createdAt: String
    }

    /// Get full customer detail with all related data.
    public func getCustomerDetail(customerId: Int64, includeFinancials: Bool) throws -> CustomerDetail {
        try db.writer.read { dbConn in
            // Customer base info
            let custRow = try Row.fetchOne(dbConn, sql: """
                SELECT id, COALESCE(company_name, name) as company_name, name as contact_name, email, phone, address, 'standard' as customer_type
                FROM customers WHERE id = ? AND deleted_at IS NULL
                """, arguments: [customerId])

            guard let row = custRow else {
                throw PeopleError.customerNotFound(customerId)
            }

            // Additional contacts
            let contactRows = try Row.fetchAll(dbConn, sql: """
                SELECT id, COALESCE(first_name || ' ' || last_name, first_name, last_name, '') as name,
                       role, phone, email
                FROM entity_contacts
                WHERE entity_type = 'customer' AND entity_id = ? AND deleted_at IS NULL
                ORDER BY is_primary DESC, first_name ASC
                """, arguments: [customerId])

            let contacts = contactRows.map { r in
                CustomerContact(
                    id: r["id"] as Int64? ?? 0,
                    name: r["name"] as String? ?? "",
                    role: r["role"] as String?,
                    phone: r["phone"] as String?,
                    email: r["email"] as String?
                )
            }

            // Job history
            let jobRows = try Row.fetchAll(dbConn, sql: """
                SELECT j.id, COALESCE(j.job_name, '') as name,
                       COALESCE(j.job_number, '') as job_number, COALESCE(j.status, 'unknown') as status,
                       j.start_date
                FROM jobs j
                JOIN job_customers jc ON jc.job_id = j.id
                WHERE jc.customer_id = ? AND j.deleted_at IS NULL
                ORDER BY j.created_at DESC
                """, arguments: [customerId])

            let jobHistory = jobRows.map { r in
                CustomerJobSummary(
                    id: r["id"] as Int64? ?? 0,
                    name: r["name"] as String? ?? "",
                    jobNumber: r["job_number"] as String? ?? "",
                    status: r["status"] as String? ?? "unknown",
                    startDate: r["start_date"] as String?
                )
            }

            // Stats
            let totalJobs = jobRows.count
            let activeJobs = jobRows.filter { ($0["status"] as String? ?? "") == "active" }.count
            let completedJobs = jobRows.filter { ($0["status"] as String? ?? "") == "completed" }.count

            var totalRevenue: Double? = nil
            var averageJobSize: Double? = nil
            if includeFinancials {
                let revenueRow = try Row.fetchOne(dbConn, sql: """
                    SELECT SUM(pr.amount) as total, AVG(pr.amount) as avg_amount
                    FROM payment_records pr
                    WHERE pr.customer_id = ? AND pr.deleted_at IS NULL
                    """, arguments: [customerId])
                totalRevenue = revenueRow?["total"] as Double?
                averageJobSize = revenueRow?["avg_amount"] as Double?
            }

            let firstJobDate = jobRows.last?["start_date"] as String?
            let lastJobDate = jobRows.first?["start_date"] as String?

            let stats = CustomerStats(
                totalJobs: totalJobs, activeJobs: activeJobs, completedJobs: completedJobs,
                totalRevenue: totalRevenue, averageJobSize: averageJobSize,
                firstJobDate: firstJobDate, lastJobDate: lastJobDate
            )

            // Communication log
            let commRows = try Row.fetchAll(dbConn, sql: """
                SELECT cc.id, cc.comm_type, cc.content,
                       COALESCE(u.display_name, 'System') as created_by,
                       cc.created_at
                FROM customer_communications cc
                LEFT JOIN users u ON u.id = cc.created_by AND u.deleted_at IS NULL
                WHERE cc.customer_id = ? AND cc.deleted_at IS NULL
                ORDER BY cc.created_at DESC
                LIMIT 50
                """, arguments: [customerId])

            let commLog = commRows.map { r in
                CommunicationEntry(
                    id: r["id"] as Int64? ?? 0,
                    commType: r["comm_type"] as String? ?? "note",
                    content: r["content"] as String? ?? "",
                    createdBy: r["created_by"] as String? ?? "System",
                    createdAt: r["created_at"] as String? ?? ""
                )
            }

            return CustomerDetail(
                customerId: customerId,
                companyName: row["company_name"] as String?,
                contactName: row["contact_name"] as String?,
                email: row["email"] as String?,
                phone: row["phone"] as String?,
                address: row["address"] as String?,
                customerType: row["customer_type"] as String?,
                contacts: contacts, jobHistory: jobHistory,
                stats: stats, communicationLog: commLog
            )
        }
    }

    /// Add a communication entry for a customer.
    @discardableResult
    public func addCommunicationEntry(customerId: Int64, commType: String, content: String, createdBy: Int64) throws -> Int64 {
        guard !commType.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("commType")
        }
        guard !content.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("content")
        }
        return try db.writer.write { dbConn in
            let customerExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM customers WHERE id = ? AND deleted_at IS NULL
                """, arguments: [customerId]) ?? 0) > 0
            guard customerExists else { throw PeopleError.customerNotFound(customerId) }
            let userExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM users WHERE id = ? AND deleted_at IS NULL AND is_active = 1
                """, arguments: [createdBy]) ?? 0) > 0
            guard userExists else { throw PeopleError.userNotFound(createdBy) }
            try dbConn.execute(sql: """
                INSERT INTO customer_communications (customer_id, comm_type, content, created_by)
                VALUES (?, ?, ?, ?)
                """, arguments: [customerId, commType, content, createdBy])
            return dbConn.lastInsertedRowID
        }
    }

    // =========================================================================
    // MARK: - Contractor Detail (44D)
    // =========================================================================

    /// Aggregated contractor rating.
    public struct ContractorRating: Sendable {
        public let qualityScore: Double
        public let onTimeScore: Double
        public let reliabilityScore: Double
        public var overallScore: Double { (qualityScore + onTimeScore + reliabilityScore) / 3.0 }
    }

    /// A note attached to a contractor.
    public struct ContractorNote: Sendable, Identifiable {
        public let id: Int64
        public let content: String
        public let createdBy: String
        public let createdAt: String
    }

    /// Job summary for contractor history.
    public struct ContractorJobSummary: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let status: String
        public let completedDate: String?
    }

    /// Get aggregated rating for a contractor (subcontractors only).
    public func getContractorRating(contractorId: Int64) throws -> ContractorRating? {
        try db.writer.read { dbConn in
            let row = try Row.fetchOne(dbConn, sql: """
                SELECT AVG(quality_score) as quality, AVG(on_time_score) as on_time,
                       AVG(reliability_score) as reliability
                FROM contractor_ratings
                WHERE contractor_id = ? AND deleted_at IS NULL
                """, arguments: [contractorId])

            guard let r = row,
                  let quality = r["quality"] as Double?,
                  let onTime = r["on_time"] as Double?,
                  let reliability = r["reliability"] as Double? else {
                return nil
            }

            return ContractorRating(
                qualityScore: quality, onTimeScore: onTime, reliabilityScore: reliability
            )
        }
    }

    /// Get job history for a contractor.
    public func getContractorJobHistory(contractorId: Int64) throws -> [ContractorJobSummary] {
        try db.writer.read { dbConn in
            // Contractors are linked via subcontractor_schedules or job_general_contractors
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT DISTINCT j.id, COALESCE(j.job_name, '') as name,
                       COALESCE(j.status, 'unknown') as status, j.completed_date
                FROM jobs j
                LEFT JOIN subcontractor_schedules ss ON ss.job_id = j.id AND ss.gc_id = ?
                LEFT JOIN job_general_contractors jgc ON jgc.job_id = j.id AND jgc.gc_id = ?
                WHERE (ss.id IS NOT NULL OR jgc.id IS NOT NULL) AND j.deleted_at IS NULL
                ORDER BY j.created_at DESC
                LIMIT 50
                """, arguments: [contractorId, contractorId])

            return rows.map { r in
                ContractorJobSummary(
                    id: r["id"] as Int64? ?? 0,
                    name: r["name"] as String? ?? "",
                    status: r["status"] as String? ?? "unknown",
                    completedDate: r["completed_date"] as String?
                )
            }
        }
    }

    /// Get notes for a contractor.
    public func getContractorNotes(contractorId: Int64) throws -> [ContractorNote] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT cn.id, cn.content,
                       COALESCE(u.display_name, 'System') as created_by,
                       cn.created_at
                FROM contractor_notes cn
                LEFT JOIN users u ON u.id = cn.created_by AND u.deleted_at IS NULL
                WHERE cn.contractor_id = ? AND cn.deleted_at IS NULL
                ORDER BY cn.created_at DESC
                """, arguments: [contractorId])

            return rows.map { r in
                ContractorNote(
                    id: r["id"] as Int64? ?? 0,
                    content: r["content"] as String? ?? "",
                    createdBy: r["created_by"] as String? ?? "System",
                    createdAt: r["created_at"] as String? ?? ""
                )
            }
        }
    }

    /// Add a note to a contractor.
    @discardableResult
    public func addContractorNote(contractorId: Int64, content: String, createdBy: Int64) throws -> Int64 {
        guard !content.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("content")
        }
        return try db.writer.write { dbConn in
            let contractorExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM general_contractors WHERE id = ? AND deleted_at IS NULL
                """, arguments: [contractorId]) ?? 0) > 0
            guard contractorExists else { throw PeopleError.contractorNotFound(contractorId) }
            let userExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM users WHERE id = ? AND deleted_at IS NULL AND is_active = 1
                """, arguments: [createdBy]) ?? 0) > 0
            guard userExists else { throw PeopleError.userNotFound(createdBy) }
            try dbConn.execute(sql: """
                INSERT INTO contractor_notes (contractor_id, content, created_by)
                VALUES (?, ?, ?)
                """, arguments: [contractorId, content, createdBy])
            return dbConn.lastInsertedRowID
        }
    }

    /// Add a rating for a contractor.
    @discardableResult
    public func addContractorRating(
        contractorId: Int64, quality: Double, onTime: Double, reliability: Double,
        ratedBy: Int64, jobId: Int64?
    ) throws -> Int64 {
        for score in [quality, onTime, reliability] {
            guard score >= 0.0 && score <= 5.0 else { throw PeopleError.invalidScore(score) }
        }
        return try db.writer.write { dbConn in
            let contractorExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM general_contractors WHERE id = ? AND deleted_at IS NULL
                """, arguments: [contractorId]) ?? 0) > 0
            guard contractorExists else { throw PeopleError.contractorNotFound(contractorId) }
            let userExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM users WHERE id = ? AND deleted_at IS NULL AND is_active = 1
                """, arguments: [ratedBy]) ?? 0) > 0
            guard userExists else { throw PeopleError.userNotFound(ratedBy) }
            try dbConn.execute(sql: """
                INSERT INTO contractor_ratings (contractor_id, quality_score, on_time_score, reliability_score, rated_by, job_id)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [contractorId, quality, onTime, reliability, ratedBy, jobId])
            return dbConn.lastInsertedRowID
        }
    }

    // =========================================================================
    // MARK: - Contact Sorting (44E)
    // =========================================================================

    /// Get contacts with sorting and active/inactive separation.
    public func getContactsSorted(sortBy: String, typeFilter: String?) throws -> (active: [ContactListItem], inactive: [ContactListItem]) {
        let orderClause: String
        switch sortBy {
        case "name":
            orderClause = "first_name ASC, last_name ASC"
        case "type":
            orderClause = "entity_type ASC, first_name ASC"
        default:
            orderClause = "updated_at DESC, first_name ASC"
        }

        do { return try db.writer.read { dbConn in
            var sql = """
                SELECT ec.id, ec.first_name, ec.last_name,
                       ec.role AS company, ec.email, ec.phone, ec.entity_type AS contact_type,
                       COALESCE(ec.is_active, 1) as is_active
                FROM entity_contacts ec
                WHERE ec.deleted_at IS NULL
                """
            var args: [any DatabaseValueConvertible] = []

            if let tf = typeFilter, !tf.isEmpty, tf != "all" {
                if tf == "active" {
                    sql += " AND COALESCE(ec.is_active, 1) = 1"
                } else if tf == "inactive" {
                    sql += " AND COALESCE(ec.is_active, 1) = 0"
                } else {
                    sql += " AND ec.entity_type = ?"
                    args.append(tf)
                }
            }

            sql += " ORDER BY \(orderClause)"

            let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))

            var active: [ContactListItem] = []
            var inactive: [ContactListItem] = []

            for r in rows {
                let item = ContactListItem(
                    id: r["id"] as Int64? ?? 0,
                    firstName: r["first_name"] as String? ?? "",
                    lastName: r["last_name"] as String? ?? "",
                    company: r["company"] as String?,
                    email: r["email"] as String?,
                    phone: r["phone"] as String?,
                    contactType: r["contact_type"] as String?
                )
                let isActive = (r["is_active"] as Int?) ?? 1
                if isActive == 1 {
                    active.append(item)
                } else {
                    inactive.append(item)
                }
            }

            return (active: active, inactive: inactive)
        }
        } catch {
            if isTableNotFoundError(error) { return (active: [], inactive: []) }
            throw error
        }
    }

    /// Fetch a single contact by ID. Returns nil if not found or deleted.
    public func getContact(id: Int64) throws -> ContactListItem? {
        do { return try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT ec.id, ec.first_name, ec.last_name,
                       ec.role AS company, ec.email, ec.phone, ec.entity_type AS contact_type
                FROM entity_contacts ec
                WHERE ec.deleted_at IS NULL AND ec.id = ?
                LIMIT 1
                """, arguments: [id])
            guard let r = rows.first else { return nil }
            return ContactListItem(
                id: r["id"] as Int64? ?? 0,
                firstName: r["first_name"] as String? ?? "",
                lastName: r["last_name"] as String? ?? "",
                company: r["company"] as String?,
                email: r["email"] as String?,
                phone: r["phone"] as String?,
                contactType: r["contact_type"] as String?
            )
        }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    /// Count contacts by type for smart cards.
    public func getContactTypeCounts() throws -> [String: Int] {
        do { return try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT COALESCE(entity_type, 'other') as ct,
                       SUM(CASE WHEN COALESCE(is_active, 1) = 1 THEN 1 ELSE 0 END) as active_count,
                       SUM(CASE WHEN COALESCE(is_active, 1) = 0 THEN 1 ELSE 0 END) as inactive_count,
                       COUNT(*) as total
                FROM entity_contacts
                WHERE deleted_at IS NULL
                GROUP BY ct
                """)

            var counts: [String: Int] = ["all": 0, "active": 0, "inactive": 0]
            for r in rows {
                let ct = r["ct"] as String? ?? "other"
                let total = r["total"] as Int? ?? 0
                let activeCount = r["active_count"] as Int? ?? 0
                let inactiveCount = r["inactive_count"] as Int? ?? 0
                counts[ct] = total
                counts["all"] = (counts["all"] ?? 0) + total
                counts["active"] = (counts["active"] ?? 0) + activeCount
                counts["inactive"] = (counts["inactive"] ?? 0) + inactiveCount
            }
            return counts
        }
        } catch {
            if isTableNotFoundError(error) { return ["all": 0, "active": 0, "inactive": 0] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Payment Tracking (44F)
    // =========================================================================

    /// Payment status for a customer.
    public struct PaymentStatus: Sendable {
        public let totalInvoiced: Double
        public let totalPaid: Double
        public let totalOverdue: Double
        public let oldestOverdueDays: Int?
        public var paymentPercent: Double { totalPaid / max(totalInvoiced, 1) }
        public var isOverdue: Bool { totalOverdue > 0 }
    }

    /// A payment record row.
    public struct PaymentRecord: Sendable, Identifiable {
        public let id: Int64
        public let customerId: Int64
        public let jobId: Int64?
        public let invoiceNumber: String?
        public let amount: Double
        public let dueDate: String
        public let paidDate: String?
        public let paidAmount: Double?
        public let status: String
        public let notes: String?
    }

    /// Customer with overdue payment alert.
    public struct CustomerPaymentAlert: Sendable, Identifiable {
        public let id: Int64
        public let customerName: String
        public let overdueAmount: Double
        public let overdueDays: Int
    }

    /// Check if payment tracking is enabled.
    public func isPaymentTrackingEnabled() throws -> Bool {
        try db.writer.read { dbConn in
            let val = try String.fetchOne(dbConn, sql: """
                SELECT value FROM settings WHERE key = 'payment_tracking_enabled'
                """)
            return val == "1"
        }
    }

    /// Enable/disable payment tracking.
    public func setPaymentTrackingEnabled(_ enabled: Bool) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE settings SET value = ? WHERE key = 'payment_tracking_enabled'
                """, arguments: [enabled ? "1" : "0"])
        }
    }

    /// Get payment tracking settings.
    public func getPaymentSettings() throws -> (termsDays: Int, warningDays: Int, autoHold: Bool) {
        try db.writer.read { dbConn in
            let terms = try Int.fetchOne(dbConn, sql: "SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_payment_terms_days'") ?? 30
            let warning = try Int.fetchOne(dbConn, sql: "SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'overdue_warning_days'") ?? 7
            let hold = try String.fetchOne(dbConn, sql: "SELECT value FROM settings WHERE key = 'auto_payment_hold'") == "1"
            return (termsDays: terms, warningDays: warning, autoHold: hold)
        }
    }

    /// Update payment tracking settings.
    public func updatePaymentSettings(termsDays: Int, warningDays: Int, autoHold: Bool) throws {
        guard termsDays > 0 else { throw PeopleError.invalidAmount(Double(termsDays)) }
        guard warningDays >= 0 else { throw PeopleError.invalidAmount(Double(warningDays)) }
        try db.writer.write { dbConn in
            try dbConn.execute(sql: "UPDATE settings SET value = ? WHERE key = 'default_payment_terms_days'", arguments: [String(termsDays)])
            try dbConn.execute(sql: "UPDATE settings SET value = ? WHERE key = 'overdue_warning_days'", arguments: [String(warningDays)])
            try dbConn.execute(sql: "UPDATE settings SET value = ? WHERE key = 'auto_payment_hold'", arguments: [autoHold ? "1" : "0"])
        }
    }

    /// Get payment status for a customer.
    public func getCustomerPaymentStatus(customerId: Int64) throws -> PaymentStatus {
        try db.writer.read { dbConn in
            let row = try Row.fetchOne(dbConn, sql: """
                SELECT COALESCE(SUM(amount), 0) as total_invoiced,
                       COALESCE(SUM(paid_amount), 0) as total_paid,
                       COALESCE(SUM(CASE WHEN status = 'overdue' THEN amount - COALESCE(paid_amount, 0) ELSE 0 END), 0) as total_overdue
                FROM payment_records
                WHERE customer_id = ? AND deleted_at IS NULL
                """, arguments: [customerId])

            let overdueRow = try Row.fetchOne(dbConn, sql: """
                SELECT MIN(due_date) as oldest_due
                FROM payment_records
                WHERE customer_id = ? AND status = 'overdue' AND deleted_at IS NULL
                """, arguments: [customerId])

            var oldestDays: Int? = nil
            if let oldest = overdueRow?["oldest_due"] as String? {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                if let dueDate = f.date(from: oldest) {
                    oldestDays = Int(Date().timeIntervalSince(dueDate) / 86400)
                }
            }

            return PaymentStatus(
                totalInvoiced: row?["total_invoiced"] as Double? ?? 0,
                totalPaid: row?["total_paid"] as Double? ?? 0,
                totalOverdue: row?["total_overdue"] as Double? ?? 0,
                oldestOverdueDays: oldestDays
            )
        }
    }

    /// Get payment records for a customer.
    public func getPaymentRecords(customerId: Int64) throws -> [PaymentRecord] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT id, customer_id, job_id, invoice_number, amount, due_date,
                       paid_date, paid_amount, status, notes
                FROM payment_records
                WHERE customer_id = ? AND deleted_at IS NULL
                ORDER BY due_date DESC
                """, arguments: [customerId])

            return rows.map { r in
                PaymentRecord(
                    id: r["id"] as Int64? ?? 0,
                    customerId: r["customer_id"] as Int64? ?? 0,
                    jobId: r["job_id"] as Int64?,
                    invoiceNumber: r["invoice_number"] as String?,
                    amount: r["amount"] as Double? ?? 0,
                    dueDate: r["due_date"] as String? ?? "",
                    paidDate: r["paid_date"] as String?,
                    paidAmount: r["paid_amount"] as Double?,
                    status: r["status"] as String? ?? "pending",
                    notes: r["notes"] as String?
                )
            }
        }
    }

    /// Create a payment record (invoice). Returns 0 if the customer is tombstoned
    /// (or if jobId is non-nil but references a tombstoned job).
    @discardableResult
    public func createPaymentRecord(
        customerId: Int64, jobId: Int64?, amount: Double, dueDate: String,
        invoiceNumber: String?, createdBy: Int64
    ) throws -> Int64 {
        guard amount > 0 else { throw PeopleError.invalidAmount(amount) }
        guard !dueDate.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("dueDate")
        }
        return try db.writer.write { dbConn in
            // Guard: customer must exist and not be tombstoned — otherwise the
            // INSERT INTO payment_records would create an orphan invoice against a
            // soft-deleted customer.
            let customerExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM customers WHERE id = ? AND deleted_at IS NULL
                """, arguments: [customerId]) ?? 0) > 0
            guard customerExists else { return 0 }

            // If jobId is provided, it must also not be tombstoned (optional FK).
            if let jid = jobId {
                let jobExists = (try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM jobs WHERE id = ? AND deleted_at IS NULL
                    """, arguments: [jid]) ?? 0) > 0
                guard jobExists else { return 0 }
            }

            try dbConn.execute(sql: """
                INSERT INTO payment_records (customer_id, job_id, amount, due_date, invoice_number, created_by)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [customerId, jobId, amount, dueDate, invoiceNumber, createdBy])
            return dbConn.lastInsertedRowID
        }
    }

    /// Record a payment against an existing invoice.
    public func recordPayment(recordId: Int64, amount: Double, paidDate: String) throws {
        guard amount > 0 else { throw PeopleError.invalidAmount(amount) }
        guard !paidDate.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PeopleError.requiredFieldEmpty("paidDate")
        }
        try db.writer.write { dbConn in
            guard let row = try Row.fetchOne(dbConn, sql: "SELECT amount, COALESCE(paid_amount, 0) as paid FROM payment_records WHERE id = ? AND deleted_at IS NULL", arguments: [recordId]) else { return }
            let invoiceAmount = row["amount"] as Double? ?? 0
            let currentPaid = row["paid"] as Double? ?? 0
            let newPaid = currentPaid + amount
            let status = newPaid >= invoiceAmount ? "paid" : "partial"

            try dbConn.execute(sql: """
                UPDATE payment_records SET paid_amount = ?, paid_date = ?, status = ?, updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [newPaid, paidDate, status, recordId])
        }
    }

    /// Get all customers with overdue payments.
    public func getOverdueCustomers() throws -> [CustomerPaymentAlert] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT c.id, COALESCE(c.company_name, c.name, 'Unknown') as customer_name,
                       SUM(pr.amount - COALESCE(pr.paid_amount, 0)) as overdue_amount,
                       MIN(pr.due_date) as oldest_due
                FROM payment_records pr
                JOIN customers c ON c.id = pr.customer_id
                WHERE pr.status = 'overdue' AND pr.deleted_at IS NULL AND c.deleted_at IS NULL
                GROUP BY c.id
                ORDER BY overdue_amount DESC
                """)

            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"

            return rows.compactMap { r in
                let daysOverdue: Int
                if let oldest = r["oldest_due"] as String?, let dueDate = f.date(from: oldest) {
                    daysOverdue = max(0, Int(Date().timeIntervalSince(dueDate) / 86400))
                } else {
                    daysOverdue = 0
                }

                return CustomerPaymentAlert(
                    id: r["id"] as Int64? ?? 0,
                    customerName: r["customer_name"] as String? ?? "Unknown",
                    overdueAmount: r["overdue_amount"] as Double? ?? 0,
                    overdueDays: daysOverdue
                )
            }
        }
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
        return message.contains("no such table") || message.contains("no such column")
    }

    /// Format a date as yyyy-MM-dd.
    private func formatDateYMD(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Parse a yyyy-MM-dd string to a Date.
    private func parseDateYMD(_ str: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: str)
    }
}
