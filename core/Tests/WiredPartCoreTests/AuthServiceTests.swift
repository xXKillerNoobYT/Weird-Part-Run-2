import Foundation
import Testing
import GRDB
import CryptoKit
@testable import WiredPartCore

@Suite("AuthService Tests", .serialized)
struct AuthServiceTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    // MARK: - PIN Hashing

    @Test("hashPin produces consistent SHA-256 hex")
    func testHashPinConsistent() throws {
        let hash1 = AuthService.hashPin("1234", salt: "test-salt")
        let hash2 = AuthService.hashPin("1234", salt: "test-salt")
        #expect(hash1 == hash2)
        #expect(hash1.count == 64) // SHA-256 = 32 bytes = 64 hex chars
    }

    @Test("hashPin produces different hashes for different PINs")
    func testHashPinDifferent() throws {
        let hash1 = AuthService.hashPin("1234", salt: "test-salt")
        let hash2 = AuthService.hashPin("5678", salt: "test-salt")
        #expect(hash1 != hash2)
    }

    @Test("verifyPinLocally returns true for correct PIN")
    func testVerifyPinCorrect() throws {
        let pin = "9876"
        let hash = AuthService.hashPin(pin, salt: "test-salt")
        #expect(AuthService.verifyPinLocally(pin: pin, storedHash: hash, salt: "test-salt"))
    }

    @Test("verifyPinLocally returns false for wrong PIN")
    func testVerifyPinWrong() throws {
        let hash = AuthService.hashPin("1234", salt: "test-salt")
        #expect(!AuthService.verifyPinLocally(pin: "0000", storedHash: hash, salt: "test-salt"))
    }

    @Test("verifyPinLocally returns false for bcrypt hash")
    func testVerifyPinBcrypt() throws {
        #expect(!AuthService.verifyPinLocally(pin: "1234", storedHash: "$2b$12$someBcryptHash", salt: "test-salt"))
    }

    // MARK: - Token Generation & Parsing

    @Test("generateLocalToken produces signed payload.signature format")
    func testGenerateToken() throws {
        let token = try #require(AuthService.generateLocalToken(userId: 42))
        #expect(!token.isEmpty)
        // Signed tokens have format: base64payload.base64signature
        let parts = token.split(separator: ".")
        #expect(parts.count == 2)
        #expect(Data(base64Encoded: String(parts[0])) != nil)
        #expect(Data(base64Encoded: String(parts[1])) != nil)
    }

    @Test("parseLocalToken round-trips correctly")
    func testParseToken() throws {
        let token = try #require(AuthService.generateLocalToken(userId: 42))
        let payload = AuthService.parseLocalToken(token)
        #expect(payload != nil)
        #expect(payload?.sub == 42)
        #expect(payload?.type == "local")
        #expect(payload?.exp ?? 0 > payload?.iat ?? 0)
    }

    @Test("parseLocalToken returns nil for garbage")
    func testParseTokenInvalid() throws {
        #expect(AuthService.parseLocalToken("not-valid-base64!!!") == nil)
    }

    @Test("parseLocalToken rejects unsigned legacy tokens (DIS-014 regression)")
    func testParseTokenRejectsUnsigned() throws {
        // Simulate a pre-PE-008a unsigned token: plain base64 payload with no signature.
        // These should now be rejected since the shim was removed 2026-04-08.
        let payload = AuthService.TokenPayload(sub: 42, iat: 1000, exp: 9999999999999, type: "local")
        let data = try JSONEncoder().encode(payload)
        let unsignedToken = data.base64EncodedString()  // no "." separator — legacy format
        #expect(AuthService.parseLocalToken(unsignedToken) == nil)
    }

    @Test("parseLocalToken rejects tampered signature")
    func testParseTokenRejectsTamperedSig() throws {
        let token = try #require(AuthService.generateLocalToken(userId: 42))
        // Flip a character in the signature portion
        let parts = token.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else { return }
        let tampered = "\(parts[0]).AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        #expect(AuthService.parseLocalToken(tampered) == nil)
    }

    // MARK: - Seed First Admin

    @Test("seedFirstAdmin creates user, hats, permissions, settings")
    func testSeedFirstAdmin() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)

        let result = try auth.seedFirstAdmin(displayName: "TestAdmin", pin: "1234")
        #expect(result.success)
        #expect(result.user != nil)
        #expect(result.user?.displayName == "TestAdmin")
        #expect(result.token != nil)
        #expect(result.message.contains("Welcome"))
    }

    @Test("seedFirstAdmin creates 7 built-in hats")
    func testSeedCreatesHats() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        _ = try auth.seedFirstAdmin(displayName: "Admin", pin: "1234")

        let hatCount = try db.writer.read { dbConn -> Int in
            try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM hats")!
        }
        #expect(hatCount == 7)
    }

    @Test("seedFirstAdmin assigns Admin hat to user")
    func testSeedAssignsAdminHat() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        let result = try auth.seedFirstAdmin(displayName: "Admin", pin: "1234")

        let hatNames = try auth.getUserHatNames(result.user!.id!)
        #expect(hatNames.contains("Admin"))
    }

    @Test("seedFirstAdmin seeds default settings")
    func testSeedCreatesSettings() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        _ = try auth.seedFirstAdmin(displayName: "Admin", pin: "1234")

        let companyName = try db.writer.read { dbConn -> String? in
            try String.fetchOne(dbConn, sql: "SELECT value FROM settings WHERE key = 'company_name'")
        }
        #expect(companyName == "Admin's Company")
    }

    @Test("seedFirstAdmin prevents double-seed")
    func testSeedPreventsDouble() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)

        _ = try auth.seedFirstAdmin(displayName: "Admin1", pin: "1234")
        let second = try auth.seedFirstAdmin(displayName: "Admin2", pin: "5678")

        #expect(!second.success)
        #expect(second.message.contains("already exist"))
    }

    // MARK: - Authentication

    @Test("authenticateByPin succeeds with correct PIN")
    func testAuthSuccess() throws {
        AuthService.resetAllLoginAttempts()
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "Admin", pin: "1234")
        let userId = seed.user!.id!

        let result = try auth.authenticateByPin(userId: userId, pin: "1234")
        #expect(result.success)
        #expect(result.user?.displayName == "Admin")
        #expect(result.token != nil)
    }

    @Test("authenticateByPin rejects wrong PIN")
    func testAuthWrongPin() throws {
        AuthService.resetAllLoginAttempts()
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "Admin", pin: "1234")
        let userId = seed.user!.id!

        let result = try auth.authenticateByPin(userId: userId, pin: "0000")
        #expect(!result.success)
        #expect(result.message == "Invalid PIN")
    }

    @Test("authenticateByPin rejects soft-deleted users even with correct PIN")
    func testAuthRejectsDeletedUser() throws {
        AuthService.resetAllLoginAttempts()
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "DeletedAdmin", pin: "1234")
        let userId = seed.user!.id!

        // Soft-delete the user — but leave is_active = 1 to simulate the
        // defense-in-depth scenario where is_active and deleted_at drift apart.
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [userId]
            )
        }

        let result = try auth.authenticateByPin(userId: userId, pin: "1234")
        #expect(!result.success,
                "Soft-deleted user must not authenticate even with correct PIN and is_active=1")
        #expect(result.message == "User not found or inactive")
    }

    @Test("getActiveUsers excludes soft-deleted users from login picker")
    func testGetActiveUsers_excludesDeletedUsers() throws {
        AuthService.resetAllLoginAttempts()
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "LoginAdmin", pin: "1234")
        let userId = seed.user!.id!

        let beforeDelete = try auth.getActiveUsers()
        #expect(beforeDelete.contains { $0.id == userId })

        // Soft-delete the user
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [userId]
            )
        }

        let afterDelete = try auth.getActiveUsers()
        #expect(!afterDelete.contains { $0.id == userId },
                "Soft-deleted users must not appear on the login screen even if is_active=1")
    }

    // MARK: - Lockout State

    @Test("lockoutSecondsRemaining returns nil when no failed attempts")
    func testLockoutNilOnFreshState() throws {
        AuthService.resetAllLoginAttempts()
        #expect(AuthService.lockoutSecondsRemaining(userId: 9001) == nil)
    }

    @Test("lockoutSecondsRemaining returns positive seconds after 5 failed PINs")
    func testLockoutAfterFiveFailures() throws {
        AuthService.resetAllLoginAttempts()
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "LockAdmin", pin: "9999")
        let userId = seed.user!.id!

        // 5 wrong attempts triggers 30-second lockout
        for _ in 1...5 {
            _ = try auth.authenticateByPin(userId: userId, pin: "0000")
        }

        let seconds = AuthService.lockoutSecondsRemaining(userId: userId)
        #expect(seconds != nil)
        #expect((seconds ?? 0) > 0)
    }

    @Test("resetAllLoginAttempts clears active lockout")
    func testResetClearsLockout() throws {
        // Use a private userId unlikely to collide with parallel tests
        // (parallel tests always create userId=1 via seedFirstAdmin)
        // We manually manipulate static state via the public reset method.
        AuthService.resetAllLoginAttempts()

        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "ResetAdmin", pin: "7777")
        let userId = seed.user!.id!

        // Trigger lockout with 3 wrong PINs (count ≥ 3 → 5s lockout)
        _ = try auth.authenticateByPin(userId: userId, pin: "0000")
        _ = try auth.authenticateByPin(userId: userId, pin: "0000")
        _ = try auth.authenticateByPin(userId: userId, pin: "0000")

        // Immediately reset — lockout should disappear regardless of timing
        AuthService.resetAllLoginAttempts()
        #expect(AuthService.lockoutSecondsRemaining(userId: userId) == nil)
    }

    @Test("lockoutSecondsRemaining returns nil after successful login clears the counter")
    func testLockoutClearedOnSuccessfulAuth() throws {
        AuthService.resetAllLoginAttempts()
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "ClearAdmin", pin: "5555")
        let userId = seed.user!.id!

        // 2 wrong attempts — not yet locked
        _ = try auth.authenticateByPin(userId: userId, pin: "0000")
        _ = try auth.authenticateByPin(userId: userId, pin: "0000")
        #expect(AuthService.lockoutSecondsRemaining(userId: userId) == nil)

        // Correct PIN clears the counter
        let result = try auth.authenticateByPin(userId: userId, pin: "5555")
        #expect(result.success)
        #expect(AuthService.lockoutSecondsRemaining(userId: userId) == nil)

        AuthService.resetAllLoginAttempts()
    }

    @Test("authenticateByPin rejects non-existent user")
    func testAuthBadUser() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)

        let result = try auth.authenticateByPin(userId: 9999, pin: "1234")
        #expect(!result.success)
        #expect(result.message.contains("not found"))
    }

    // MARK: - Permissions

    @Test("Admin user has all expected permissions")
    func testAdminPermissions() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "Admin", pin: "1234")
        let userId = seed.user!.id!

        let perms = try auth.getUserPermissions(userId)
        #expect(perms.contains("manage_settings"))
        #expect(perms.contains("view_parts_catalog"))
        #expect(perms.contains("manage_remote_sync"))
        // companion_vote_power must be seeded for fresh installs (not just via migration)
        #expect(perms.contains("companion_vote_power"))
        #expect(perms.contains("vote_veto"))
    }

    @Test("hasPermission returns true for admin")
    func testHasPermission() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "Admin", pin: "1234")
        let userId = seed.user!.id!

        #expect(try auth.hasPermission(userId, permissionKey: "manage_settings"))
        #expect(try auth.hasPermission(userId, permissionKey: "view_parts_catalog"))
    }

    @Test("hasPermission returns false for non-existent permission")
    func testHasPermissionFalse() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "Admin", pin: "1234")
        let userId = seed.user!.id!

        #expect(try !auth.hasPermission(userId, permissionKey: "nonexistent_perm"))
    }

    // MARK: - User Profile

    @Test("getLocalUserProfile builds full profile from token")
    func testGetUserProfile() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "Admin", pin: "1234")

        let profile = try auth.getLocalUserProfile(token: seed.token!)
        #expect(profile.displayName == "Admin")
        #expect(profile.isActive)
        #expect(!profile.hats.isEmpty)
        #expect(profile.hats[0].name == "Admin")
        #expect(!profile.permissions.isEmpty)
    }

    @Test("getLocalUserProfile throws for invalid token")
    func testProfileInvalidToken() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)

        #expect(throws: AuthService.AuthError.self) {
            _ = try auth.getLocalUserProfile(token: "garbage-token")
        }
    }

    // MARK: - Legacy PIN Hash Tracking (PE-008c)

    @Test("getLegacyHashedUserCount returns 0 when all users have pin_salt")
    func testLegacyCountZeroWhenSalted() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        _ = try auth.seedFirstAdmin(displayName: "Admin", pin: "1234")
        #expect(try auth.getLegacyHashedUserCount() == 0)
    }

    @Test("getLegacyHashedUserCount returns 1 for user with NULL pin_salt")
    func testLegacyCountOneLegacyUser() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        _ = try auth.seedFirstAdmin(displayName: "Admin", pin: "1234")

        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO users (display_name, pin_hash, pin_salt, is_active) VALUES ('Legacy', 'deadbeef', NULL, 1)"
            )
        }

        #expect(try auth.getLegacyHashedUserCount() == 1)
    }

    @Test("getLegacyHashedUserCount ignores placeholder hashes and inactive users")
    func testLegacyCountIgnoresPlaceholdersAndInactive() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)

        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO users (display_name, pin_hash, pin_salt, is_active) VALUES ('PH', '__PLACEHOLDER_HASH__', NULL, 1)"
            )
            try dbConn.execute(
                sql: "INSERT INTO users (display_name, pin_hash, pin_salt, is_active) VALUES ('Inactive', 'oldhash', NULL, 0)"
            )
        }

        #expect(try auth.getLegacyHashedUserCount() == 0)
    }

    @Test("getLegacyHashedUserCount drops to 0 after legacy user logs in")
    func testLegacyCountDecrementOnLogin() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        _ = try auth.seedFirstAdmin(displayName: "Admin", pin: "5555")

        // Build a legacy hash (SHA256("9999:wiredpart") with no iterations, no per-user salt)
        let legacyHash = SHA256.hash(data: Data("9999:wiredpart".utf8))
            .map { String(format: "%02x", $0) }.joined()

        var legacyUserId: Int64 = 0
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO users (display_name, pin_hash, pin_salt, is_active) VALUES ('Worker', ?, NULL, 1)",
                arguments: [legacyHash]
            )
            legacyUserId = dbConn.lastInsertedRowID
        }

        #expect(try auth.getLegacyHashedUserCount() == 1)

        // Login triggers automatic re-hash with a per-user salt
        let result = try auth.authenticateByPin(userId: legacyUserId, pin: "9999")
        #expect(result.success)
        #expect(try auth.getLegacyHashedUserCount() == 0)
    }

    // MARK: - Active Users

    @Test("getActiveUsers returns only active users")
    func testGetActiveUsers() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        _ = try auth.seedFirstAdmin(displayName: "Admin", pin: "1234")

        // Add an inactive user
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO users (display_name, pin_hash, is_active) VALUES ('Inactive', 'nohash', 0)"
            )
        }

        let active = try auth.getActiveUsers()
        #expect(active.count == 1)
        #expect(active[0].displayName == "Admin")
    }

    // MARK: - createUser

    @Test("createUser inserts a new active user and returns a valid id")
    func testCreateUser() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        _ = try auth.seedFirstAdmin(displayName: "Admin", pin: "0000")

        let newId = try auth.createUser(displayName: "Bob", pin: "5678", email: "bob@example.com")
        #expect(newId > 0)

        let user = try auth.getUser(newId)
        #expect(user?.displayName == "Bob")
        #expect(user?.email == "bob@example.com")
        #expect(user?.isActive == 1)
    }

    @Test("createUser stores a salted pin that authenticates correctly")
    func testCreateUserPinAuthenticates() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        _ = try auth.seedFirstAdmin(displayName: "Admin", pin: "0000")

        let newId = try auth.createUser(displayName: "Alice", pin: "4321")
        let result = try auth.authenticateByPin(userId: newId, pin: "4321")
        #expect(result.success)
    }

    // MARK: - Hat Permissions

    @Test("addHatPermission and getHatPermissions round-trip")
    func testAddAndGetHatPermissions() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        _ = try auth.seedFirstAdmin(displayName: "Admin", pin: "0000")

        let hatId = try db.writer.write { dbConn -> Int64 in
            try dbConn.execute(sql: "INSERT INTO hats (name, level) VALUES ('TestHat', 1)")
            return dbConn.lastInsertedRowID
        }

        try auth.addHatPermission(hatId: hatId, permissionKey: "can_edit")
        try auth.addHatPermission(hatId: hatId, permissionKey: "can_delete")

        let perms = try auth.getHatPermissions(hatId)
        #expect(perms.contains("can_edit"))
        #expect(perms.contains("can_delete"))
        #expect(perms.count == 2)
    }

    @Test("addHatPermission is idempotent (INSERT OR IGNORE)")
    func testAddHatPermissionIdempotent() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        _ = try auth.seedFirstAdmin(displayName: "Admin", pin: "0000")

        let hatId = try db.writer.write { dbConn -> Int64 in
            try dbConn.execute(sql: "INSERT INTO hats (name, level) VALUES ('Dup Hat', 2)")
            return dbConn.lastInsertedRowID
        }

        try auth.addHatPermission(hatId: hatId, permissionKey: "can_view")
        try auth.addHatPermission(hatId: hatId, permissionKey: "can_view") // duplicate — should not throw

        let perms = try auth.getHatPermissions(hatId)
        #expect(perms.count == 1)
    }

    @Test("removeHatPermission deletes the specified permission")
    func testRemoveHatPermission() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        _ = try auth.seedFirstAdmin(displayName: "Admin", pin: "0000")

        let hatId = try db.writer.write { dbConn -> Int64 in
            try dbConn.execute(sql: "INSERT INTO hats (name, level) VALUES ('RemoveHat', 1)")
            return dbConn.lastInsertedRowID
        }

        try auth.addHatPermission(hatId: hatId, permissionKey: "can_edit")
        try auth.addHatPermission(hatId: hatId, permissionKey: "can_delete")
        try auth.removeHatPermission(hatId: hatId, permissionKey: "can_edit")

        let perms = try auth.getHatPermissions(hatId)
        #expect(!perms.contains("can_edit"))
        #expect(perms.contains("can_delete"))
    }

    // MARK: - getUserHats

    @Test("getUserHats returns hat summaries for a seeded admin")
    func testGetUserHats() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        let result = try auth.seedFirstAdmin(displayName: "Admin", pin: "0000")

        let hats = try auth.getUserHats(result.user!.id!)
        #expect(!hats.isEmpty)
        #expect(hats.contains(where: { $0.name == "Admin" }))
    }

    @Test("getUserHats returns empty for user with no hats")
    func testGetUserHatsEmpty() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        _ = try auth.seedFirstAdmin(displayName: "Admin", pin: "0000")

        let userId = try auth.createUser(displayName: "Bare User", pin: "1111")
        let hats = try auth.getUserHats(userId)
        #expect(hats.isEmpty)
    }

    // MARK: - listRegisteredDevices

    @Test("listRegisteredDevices returns empty on fresh database")
    func testListRegisteredDevicesEmpty() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)

        let devices = try auth.listRegisteredDevices()
        #expect(devices.isEmpty)
    }

    // MARK: - listActiveSessions / deactivateSession

    @Test("listActiveSessions returns empty on fresh database")
    func testListActiveSessionsEmpty() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)

        let sessions = try auth.listActiveSessions()
        #expect(sessions.isEmpty)
    }

    @Test("deactivateSession marks a session as deactivated")
    func testDeactivateSession() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)

        let rowId = try db.writer.write { dbConn -> Int64 in
            try dbConn.execute(sql: """
                INSERT INTO _device_registry (device_id, device_name, is_trusted, is_deactivated, last_seen_at)
                VALUES ('abc-device-123', 'iPhone 14', 1, 0, datetime('now'))
            """)
            return dbConn.lastInsertedRowID
        }

        var sessions = try auth.listActiveSessions()
        #expect(sessions.count == 1)
        #expect(sessions[0].userId == "abc-device-123")

        try auth.deactivateSession(sessionId: "\(rowId)")

        sessions = try auth.listActiveSessions()
        #expect(sessions.isEmpty)
    }

    @Test("listRegisteredDevices shows Unassigned for soft-deleted assigned user")
    func testListRegisteredDevicesHidesDeletedAssignedUser() throws {
        let env = try E2ETestHelpers.setUp()
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO devices (device_name, device_fingerprint, assigned_user_id)
                VALUES ('Test Phone', 'fp-test-del-user', ?)
                """, arguments: [env.adminUserId])
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        let devices = try env.auth.listRegisteredDevices()
        let device = devices.first(where: { $0.name == "Test Phone" })
        #expect(device != nil)
        #expect(device?.assignedUser == "Unassigned")
    }

    @Test("getLegacyHashedUsers returns users with pin_salt IS NULL")
    func testGetLegacyHashedUsers_returnsUnmigratedUser() throws {
        let env = try E2ETestHelpers.setUp()
        // Insert a user with legacy hash format (no pin_salt, no bcrypt prefix)
        let legacyHash = AuthService.legacyHashPin("4321")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, pin_salt, is_active, created_at, updated_at)
                VALUES ('Legacy User', ?, NULL, 1, datetime('now'), datetime('now'))
                """, arguments: [legacyHash])
        }
        let users = try env.auth.getLegacyHashedUsers()
        #expect(users.contains(where: { $0.displayName == "Legacy User" }))
    }

    @Test("getLegacyHashedUsers excludes migrated users")
    func testGetLegacyHashedUsers_excludesMigratedUser() throws {
        let env = try E2ETestHelpers.setUp()
        // adminUserId was created with modern hash (has pin_salt) — should not appear
        let users = try env.auth.getLegacyHashedUsers()
        let adminId = env.adminUserId
        #expect(!users.contains(where: { $0.id == adminId }))
    }

    @Test("getLegacyHashedUsers excludes soft-deleted users")
    func testGetLegacyHashedUsers_excludesDeletedLegacyUser() throws {
        let env = try E2ETestHelpers.setUp()
        let legacyHash = AuthService.legacyHashPin("1111")
        var insertedId: Int64 = 0
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, pin_salt, is_active, created_at, updated_at)
                VALUES ('Deleted Legacy', ?, NULL, 1, datetime('now'), datetime('now'))
                """, arguments: [legacyHash])
            insertedId = db.lastInsertedRowID
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [insertedId])
        }
        let users = try env.auth.getLegacyHashedUsers()
        #expect(!users.contains(where: { $0.id == insertedId }))
    }

    // MARK: - Input validation (iter 74)

    @Test("createUser rejects blank displayName")
    func testCreateUser_rejectsBlankDisplayName() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: AuthService.AuthError.self) {
            _ = try env.auth.createUser(displayName: "   ", pin: "1234")
        }
    }

    @Test("createUser rejects invalid PIN formats")
    func testCreateUser_rejectsInvalidPin() throws {
        let env = try E2ETestHelpers.setUp()
        // Too short
        #expect(throws: AuthService.AuthError.self) {
            _ = try env.auth.createUser(displayName: "Alice", pin: "12")
        }
        // Non-numeric
        #expect(throws: AuthService.AuthError.self) {
            _ = try env.auth.createUser(displayName: "Bob", pin: "abcd")
        }
        // Too long
        #expect(throws: AuthService.AuthError.self) {
            _ = try env.auth.createUser(displayName: "Cory", pin: "123456789")
        }
    }

    @Test("addHatPermission rejects blank key and non-existent hat")
    func testAddHatPermission_rejectsInvalidInputs() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: AuthService.AuthError.self) {
            try env.auth.addHatPermission(hatId: 1, permissionKey: "   ")
        }
        // Non-existent hat
        #expect(throws: AuthService.AuthError.self) {
            try env.auth.addHatPermission(hatId: 99999, permissionKey: "manage_devices")
        }
    }

    // MARK: - PIN Change + SQLCipher

    @Test("changePin keeps DB openable with device bootstrap key after restart")
    func testChangePinKeepsBootstrapKeyAfterRestart() throws {
        AuthService.resetAllLoginAttempts()

        let tmpDir = NSTemporaryDirectory()
        let dbPath = (tmpDir as NSString).appendingPathComponent("wp_pin_restart_test_\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(atPath: dbPath)
            try? FileManager.default.removeItem(atPath: dbPath + "-wal")
            try? FileManager.default.removeItem(atPath: dbPath + "-shm")
        }

        let bootstrapKeyHex = CipherKeyManager.deriveKey(
            pin: "device-bootstrap",
            salt: Data(repeating: 0x34, count: 32)
        )
        let db = try AppDatabase.openEncryptedDatabase(atPath: dbPath, keyHex: bootstrapKeyHex)
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "Admin", pin: "1234")
        let userId = try #require(seed.user?.id)

        #expect(try auth.changePin(userId: userId, oldPin: "1234", newPin: "9876"))
        try (db.writer as? DatabasePool)?.close()

        let reopened = try AppDatabase.openEncryptedDatabase(atPath: dbPath, keyHex: bootstrapKeyHex)
        let reopenedAuth = AuthService(db: reopened)
        let authResult = try reopenedAuth.authenticateByPin(userId: userId, pin: "9876")
        try (reopened.writer as? DatabasePool)?.close()

        #expect(authResult.success)
    }

    @Test("testDatabaseRekeyLowLevel — old key fails, new key works, rows preserved")
    func testDatabaseRekeyLowLevel() throws {
        AuthService.resetAllLoginAttempts()

        let tmpDir = NSTemporaryDirectory()
        let dbPath = (tmpDir as NSString).appendingPathComponent("wp_pinchange_test_\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(atPath: dbPath)
            try? FileManager.default.removeItem(atPath: dbPath + "-wal")
            try? FileManager.default.removeItem(atPath: dbPath + "-shm")
        }

        // Derive an initial key.
        let salt = Data(repeating: 0x12, count: 32)
        let oldPin = "1111"
        let newPin = "9999"
        let oldKeyHex = CipherKeyManager.deriveKey(pin: oldPin, salt: salt)
        let newKeyHex = CipherKeyManager.deriveKey(pin: newPin, salt: salt)
        #expect(oldKeyHex != newKeyHex)

        // Open an encrypted file-based DB with old key.
        let pool = try AppDatabase.makeEncryptedPool(path: dbPath, keyHex: oldKeyHex)

        // Seed a minimal schema + row so we can verify data survives re-key.
        try pool.write { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS _rekey_test (v TEXT)")
            try db.execute(sql: "INSERT INTO _rekey_test (v) VALUES ('preserved')")
        }

        // Re-key to new key.
        try AppDatabase.rekey(pool: pool, newKeyHex: newKeyHex)
        try pool.close()

        // Verify: old key CANNOT open the DB.
        var oldKeyFailed = false
        do {
            let badPool = try AppDatabase.makeEncryptedPool(path: dbPath, keyHex: oldKeyHex)
            try badPool.read { db in
                _ = try Row.fetchOne(db, sql: "SELECT 1 FROM _rekey_test LIMIT 1")
            }
            try badPool.close()
        } catch {
            oldKeyFailed = true
        }
        #expect(oldKeyFailed, "Old key should not open re-keyed DB")

        // Verify: new key CAN open the DB and rows are preserved.
        let goodPool = try AppDatabase.makeEncryptedPool(path: dbPath, keyHex: newKeyHex)
        let value: String? = try goodPool.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT v FROM _rekey_test LIMIT 1")
            return row?["v"]
        }
        try goodPool.close()
        #expect(value == "preserved", "Rows must survive re-key")
    }

    // MARK: - hasPermission backdoor fix (#366)

    @Test("hasPermission returns true for an active admin user (regression guard)")
    func testHasPermission_returnsTrueForActiveUser() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "ActiveAdmin", pin: "1234")
        let userId = seed.user!.id!

        #expect(try auth.hasPermission(userId, permissionKey: "manage_settings"),
                "hasPermission must return true for an active admin with the correct key")
    }

    @Test("hasPermission returns false after user is soft-deleted even if user_hats row is still active")
    func testHasPermission_returnsFalseAfterSoftDelete() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "SoftDeletedAdmin", pin: "1234")
        let userId = seed.user!.id!

        // Confirm permission exists before deletion
        #expect(try auth.hasPermission(userId, permissionKey: "manage_settings"))

        // Soft-delete the user only — leave user_hats untouched to validate the JOIN guard
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE users SET deleted_at = datetime('now'), is_active = 0 WHERE id = ?",
                arguments: [userId]
            )
        }

        #expect(try !auth.hasPermission(userId, permissionKey: "manage_settings"),
                "hasPermission must return false for a soft-deleted user even if their user_hats row is still active")
    }

    @Test("getUserPermissions returns empty for a soft-deleted user")
    func testGetUserPermissions_emptyForSoftDeletedUser() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "PermDeletedAdmin", pin: "1234")
        let userId = seed.user!.id!

        let before = try auth.getUserPermissions(userId)
        #expect(!before.isEmpty, "admin must have permissions before deletion")

        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE users SET deleted_at = datetime('now'), is_active = 0 WHERE id = ?",
                arguments: [userId]
            )
        }

        let after = try auth.getUserPermissions(userId)
        #expect(after.isEmpty,
                "getUserPermissions must return empty for a soft-deleted user to prevent permission leakage")
    }

    @Test("softDeleteUser sets deleted_at and is_active=0 on the user row")
    func testSoftDeleteUser_marksUserDeleted() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "ToDelete", pin: "1234")
        let userId = seed.user!.id!

        try auth.softDeleteUser(userId: userId)

        let row = try db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: "SELECT deleted_at, is_active FROM users WHERE id = ?",
                             arguments: [userId])
        }
        let r = try #require(row)
        #expect((r["deleted_at"] as String?) != nil, "deleted_at must be set after softDeleteUser")
        #expect((r["is_active"] as Int) == 0, "is_active must be 0 after softDeleteUser")
    }

    @Test("softDeleteUser cascades to deactivate user_hats rows")
    func testSoftDeleteUser_cascadesUserHats() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "HatCascade", pin: "1234")
        let userId = seed.user!.id!

        // Confirm hat assignment exists and is active before delete
        let countBefore = try db.writer.read { dbConn in
            try Int.fetchOne(dbConn,
                sql: "SELECT COUNT(*) FROM user_hats WHERE user_id = ? AND is_active = 1 AND deleted_at IS NULL",
                arguments: [userId]) ?? 0
        }
        #expect(countBefore > 0, "admin must have at least one active hat before soft-delete")

        try auth.softDeleteUser(userId: userId)

        let countAfter = try db.writer.read { dbConn in
            try Int.fetchOne(dbConn,
                sql: "SELECT COUNT(*) FROM user_hats WHERE user_id = ? AND is_active = 1 AND deleted_at IS NULL",
                arguments: [userId]) ?? 0
        }
        #expect(countAfter == 0,
                "softDeleteUser must cascade-deactivate all user_hats rows for the deleted user")
    }

    // MARK: - Migration 078: forecasting permission backfill (#4258864571)

    /// Run the migration 078 backfill SQL in the context of an already-seeded database.
    /// This simulates the upgrade scenario: hats exist, forecasting keys are missing, migration adds them.
    private func applyMigration078BackfillSQL(_ db: AppDatabase) throws {
        let permissions = [
            "forecasting.approve_recommendation",
            "forecasting.dismiss_recommendation",
        ]
        let hats = ["Admin", "Manager"]
        try db.writer.write { dbConn in
            for permKey in permissions {
                for hatName in hats {
                    try dbConn.execute(
                        sql: """
                            INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
                            SELECT id, ? FROM hats WHERE name = ?
                            """,
                        arguments: [permKey, hatName]
                    )
                }
            }
        }
    }

    @Test("migration078 backfills forecasting permissions into existing Admin hat")
    func testMigration078_backfillsForecastingPermissions_Admin() throws {
        // Use E2ETestHelpers.setUp() so that seedFirstAdmin() populates the hats table.
        // freshDB() alone does NOT insert hat rows — hats are created by seedFirstAdmin(),
        // so migration 078 (which runs during DB init before hats exist) is a no-op on
        // fresh databases. The migration matters for EXISTING (pre-upgrade) databases.
        let env = try E2ETestHelpers.setUp()

        // Simulate pre-upgrade state: delete the forecasting permission keys that were
        // seeded by defaultPermissionMap so we can verify the migration restores them.
        try env.db.writer.write { dbConn in
            try dbConn.execute(sql: """
                DELETE FROM hat_permissions
                WHERE permission_key IN (
                    'forecasting.approve_recommendation',
                    'forecasting.dismiss_recommendation'
                )
                """)
        }

        // Re-apply the migration 078 backfill SQL
        try applyMigration078BackfillSQL(env.db)

        let adminApprove = try env.db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM hat_permissions hp
                JOIN hats h ON h.id = hp.hat_id
                WHERE h.name = 'Admin' AND hp.permission_key = 'forecasting.approve_recommendation'
                """) ?? 0
        }
        let adminDismiss = try env.db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM hat_permissions hp
                JOIN hats h ON h.id = hp.hat_id
                WHERE h.name = 'Admin' AND hp.permission_key = 'forecasting.dismiss_recommendation'
                """) ?? 0
        }
        #expect(adminApprove == 1, "Admin hat must have forecasting.approve_recommendation after backfill")
        #expect(adminDismiss == 1, "Admin hat must have forecasting.dismiss_recommendation after backfill")
    }

    @Test("migration078 backfills forecasting permissions into existing Manager hat")
    func testMigration078_backfillsForecastingPermissions_Manager() throws {
        let env = try E2ETestHelpers.setUp()

        try env.db.writer.write { dbConn in
            try dbConn.execute(sql: """
                DELETE FROM hat_permissions
                WHERE permission_key IN (
                    'forecasting.approve_recommendation',
                    'forecasting.dismiss_recommendation'
                )
                """)
        }

        try applyMigration078BackfillSQL(env.db)

        let managerApprove = try env.db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM hat_permissions hp
                JOIN hats h ON h.id = hp.hat_id
                WHERE h.name = 'Manager' AND hp.permission_key = 'forecasting.approve_recommendation'
                """) ?? 0
        }
        let managerDismiss = try env.db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM hat_permissions hp
                JOIN hats h ON h.id = hp.hat_id
                WHERE h.name = 'Manager' AND hp.permission_key = 'forecasting.dismiss_recommendation'
                """) ?? 0
        }
        #expect(managerApprove == 1, "Manager hat must have forecasting.approve_recommendation after backfill")
        #expect(managerDismiss == 1, "Manager hat must have forecasting.dismiss_recommendation after backfill")
    }

    @Test("migration078 is idempotent — duplicate INSERT OR IGNORE does not create extra rows")
    func testMigration078_isIdempotent() throws {
        let env = try E2ETestHelpers.setUp()

        // Run the backfill twice (first run: keys already seeded; second run: idempotent)
        try applyMigration078BackfillSQL(env.db)
        try applyMigration078BackfillSQL(env.db)

        // Each (hat, key) pair must appear exactly once
        let duplicates = try env.db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM (
                    SELECT hp.hat_id, hp.permission_key, COUNT(*) AS cnt
                    FROM hat_permissions hp
                    JOIN hats h ON h.id = hp.hat_id
                    WHERE h.name IN ('Admin', 'Manager')
                      AND hp.permission_key IN (
                          'forecasting.approve_recommendation',
                          'forecasting.dismiss_recommendation'
                      )
                    GROUP BY hp.hat_id, hp.permission_key
                    HAVING cnt > 1
                )
                """) ?? 0
        }
        #expect(duplicates == 0, "INSERT OR IGNORE must not create duplicate hat_permissions rows")
    }
}

