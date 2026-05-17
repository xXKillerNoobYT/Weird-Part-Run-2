import Foundation
import GRDB

/// Shared authorization gate for service-layer mutation methods.
///
/// UI permission checks are defense-in-breadth only. Service methods that accept an
/// actor user id and write audit fields must verify that actor against the local
/// hat permission tables before performing the write.
public enum ServicePermissionGate {
    public enum GateError: Error, Sendable, Equatable, LocalizedError {
        case insufficientPermissions(required: String)

        public var errorDescription: String? {
            switch self {
            case .insufficientPermissions(let required):
                return "You don't have permission to perform this action (required: \(required))"
            }
        }
    }

    public static func hasPermission(_ dbConn: Database, userId: Int64, permissionKey: String) throws -> Bool {
        let count = try Int.fetchOne(
            dbConn,
            sql: """
                SELECT COUNT(*)
                FROM user_hats uh
                JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
                JOIN users u ON u.id = uh.user_id
                WHERE uh.user_id = ?
                  AND uh.is_active = 1
                  AND uh.deleted_at IS NULL
                  AND u.is_active = 1
                  AND u.deleted_at IS NULL
                  AND hp.permission_key = ?
                LIMIT 1
                """,
            arguments: [userId, permissionKey]
        ) ?? 0
        return count > 0
    }

    public static func requirePermission(_ dbConn: Database, userId: Int64, permissionKey: String) throws {
        guard try hasPermission(dbConn, userId: userId, permissionKey: permissionKey) else {
            throw GateError.insufficientPermissions(required: permissionKey)
        }
    }

    public static func requirePermission(_ dbConn: Database, userId: Int64?, permissionKey: String) throws {
        guard let userId else {
            throw GateError.insufficientPermissions(required: permissionKey)
        }
        try requirePermission(dbConn, userId: userId, permissionKey: permissionKey)
    }
}
