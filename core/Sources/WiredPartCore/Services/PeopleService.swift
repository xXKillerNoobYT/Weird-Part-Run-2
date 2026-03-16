import Foundation
import GRDB

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

    public init(db: AppDatabase) {
        self.db = db
    }

    // =========================================================================
    // MARK: - Error Types
    // =========================================================================

    public enum PeopleError: Error, Sendable {
        case employeeNotFound(Int64)
        case customerNotFound(Int64)
        case contactNotFound(Int64)
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

        public init(
            id: Int64, displayName: String, email: String, phone: String?,
            status: String, role: String,
            createdAt: String?, updatedAt: String?, deletedAt: String?,
            hats: [HatInfo], teams: [TeamMembershipInfo]
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
                    whereClauses.append("u.status = ?")
                    args.append(status)
                }

                let sql = """
                    SELECT u.id, u.display_name, u.email, u.phone, u.status, u.role,
                           GROUP_CONCAT(h.name, ', ') AS hat_names
                    FROM users u
                    LEFT JOIN user_hats uh ON uh.user_id = u.id
                    LEFT JOIN hats h ON h.id = uh.hat_id AND h.deleted_at IS NULL
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
                    SELECT id, display_name, email, phone, status, role,
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
                        WHERE uh.user_id = ? AND h.deleted_at IS NULL
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
                        FROM team_members tm
                        JOIN teams t ON t.id = tm.team_id AND t.deleted_at IS NULL
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
                // If teams/team_members tables don't exist yet, leave empty
                if !isTableNotFoundError(error) { throw error }
            }

            return EmployeeDetail(
                id: userRow["id"] ?? 0,
                displayName: userRow["display_name"] ?? userRow["email"] ?? "Unknown",
                email: userRow["email"] ?? "",
                phone: userRow["phone"] as String?,
                status: userRow["status"] ?? "active",
                role: userRow["role"] ?? "user",
                createdAt: userRow["created_at"] as String?,
                updatedAt: userRow["updated_at"] as String?,
                deletedAt: userRow["deleted_at"] as String?,
                hats: hats,
                teams: teams
            )
        }
        guard let result else { throw PeopleError.employeeNotFound(id) }
        return result
    }

    // =========================================================================
    // MARK: - 2. Customers
    // =========================================================================

    /// List customers with optional search filter.
    /// Joins to users table for contact name via user_id.
    public func listCustomers(search: String? = nil) throws -> [CustomerListItem] {
        do {
            return try db.writer.read { dbConn -> [CustomerListItem] in
                var whereClauses = ["c.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("(c.company_name LIKE ? OR u.display_name LIKE ? OR u.email LIKE ?)")
                    let pattern = "%\(search)%"
                    args.append(pattern)
                    args.append(pattern)
                    args.append(pattern)
                }

                let sql = """
                    SELECT c.id, c.company_name,
                           COALESCE(u.display_name, u.email) AS contact_name,
                           u.email, u.phone
                    FROM customers c
                    LEFT JOIN users u ON u.id = c.user_id
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY c.company_name ASC
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

    /// List contractors (contacts with contact_type = 'contractor') with optional search.
    public func listContractors(search: String? = nil) throws -> [ContractorListItem] {
        do {
            return try db.writer.read { dbConn -> [ContractorListItem] in
                var whereClauses = ["co.deleted_at IS NULL", "co.contact_type = 'contractor'"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("(co.first_name LIKE ? OR co.last_name LIKE ? OR co.company LIKE ? OR co.email LIKE ?)")
                    let pattern = "%\(search)%"
                    args.append(pattern)
                    args.append(pattern)
                    args.append(pattern)
                    args.append(pattern)
                }

                let sql = """
                    SELECT co.id, co.first_name, co.last_name, co.company, co.email, co.phone
                    FROM contacts co
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY co.last_name ASC, co.first_name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    ContractorListItem(
                        id: row["id"] ?? 0,
                        firstName: row["first_name"] ?? "",
                        lastName: row["last_name"] ?? "",
                        company: row["company"] as String?,
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

    /// List all contacts with optional search and contact type filter.
    public func listContacts(
        search: String? = nil,
        contactType: String? = nil
    ) throws -> [ContactListItem] {
        do {
            return try db.writer.read { dbConn -> [ContactListItem] in
                var whereClauses = ["co.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("(co.first_name LIKE ? OR co.last_name LIKE ? OR co.company LIKE ? OR co.email LIKE ?)")
                    let pattern = "%\(search)%"
                    args.append(pattern)
                    args.append(pattern)
                    args.append(pattern)
                    args.append(pattern)
                }
                if let contactType, !contactType.isEmpty {
                    whereClauses.append("co.contact_type = ?")
                    args.append(contactType)
                }

                let sql = """
                    SELECT co.id, co.first_name, co.last_name, co.company,
                           co.email, co.phone, co.contact_type
                    FROM contacts co
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY co.last_name ASC, co.first_name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    ContactListItem(
                        id: row["id"] ?? 0,
                        firstName: row["first_name"] ?? "",
                        lastName: row["last_name"] ?? "",
                        company: row["company"] as String?,
                        email: row["email"] as String?,
                        phone: row["phone"] as String?,
                        contactType: row["contact_type"] as String?
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
                           COALESCE((SELECT COUNT(*) FROM team_members tm
                                     WHERE tm.team_id = t.id AND tm.deleted_at IS NULL), 0) AS member_count
                    FROM teams t
                    LEFT JOIN users u ON u.id = t.leader_id
                    WHERE t.deleted_at IS NULL
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
                                     WHERE uh.hat_id = h.id), 0) AS user_count
                    FROM hats h
                    WHERE h.deleted_at IS NULL
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

    // =========================================================================
    // MARK: - 7. People Stats
    // =========================================================================

    /// Get aggregate people statistics: total/active employees, customers, contacts.
    public func getPeopleStats() throws -> PeopleStats {
        let totalEmployees = try safeCount(
            sql: "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL"
        )
        let activeEmployees = try safeCount(
            sql: "SELECT COUNT(*) FROM users WHERE status = 'active' AND deleted_at IS NULL"
        )
        let totalCustomers = try safeCount(
            sql: "SELECT COUNT(*) FROM customers WHERE deleted_at IS NULL"
        )
        let totalContacts = try safeCount(
            sql: "SELECT COUNT(*) FROM contacts WHERE deleted_at IS NULL"
        )
        return PeopleStats(
            totalEmployees: totalEmployees,
            activeEmployees: activeEmployees,
            totalCustomers: totalCustomers,
            totalContacts: totalContacts
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
