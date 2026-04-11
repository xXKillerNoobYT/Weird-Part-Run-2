import Foundation
import Testing
import GRDB
import CryptoKit
@testable import WiredPartCore

@Suite("AuthService Tests")
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
        let db = try freshDB()
        let auth = AuthService(db: db)
        let seed = try auth.seedFirstAdmin(displayName: "Admin", pin: "1234")
        let userId = seed.user!.id!

        let result = try auth.authenticateByPin(userId: userId, pin: "0000")
        #expect(!result.success)
        #expect(result.message == "Invalid PIN")
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
}
