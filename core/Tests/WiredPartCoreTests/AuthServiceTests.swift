import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("AuthService Tests")
struct AuthServiceTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    // MARK: - PIN Hashing

    @Test("hashPin produces consistent SHA-256 hex")
    func testHashPinConsistent() throws {
        let hash1 = AuthService.hashPin("1234")
        let hash2 = AuthService.hashPin("1234")
        #expect(hash1 == hash2)
        #expect(hash1.count == 64) // SHA-256 = 32 bytes = 64 hex chars
    }

    @Test("hashPin produces different hashes for different PINs")
    func testHashPinDifferent() throws {
        let hash1 = AuthService.hashPin("1234")
        let hash2 = AuthService.hashPin("5678")
        #expect(hash1 != hash2)
    }

    @Test("verifyPinLocally returns true for correct PIN")
    func testVerifyPinCorrect() throws {
        let pin = "9876"
        let hash = AuthService.hashPin(pin)
        #expect(AuthService.verifyPinLocally(pin: pin, storedHash: hash))
    }

    @Test("verifyPinLocally returns false for wrong PIN")
    func testVerifyPinWrong() throws {
        let hash = AuthService.hashPin("1234")
        #expect(!AuthService.verifyPinLocally(pin: "0000", storedHash: hash))
    }

    @Test("verifyPinLocally returns false for bcrypt hash")
    func testVerifyPinBcrypt() throws {
        #expect(!AuthService.verifyPinLocally(pin: "1234", storedHash: "$2b$12$someBcryptHash"))
    }

    // MARK: - Token Generation & Parsing

    @Test("generateLocalToken produces valid base64")
    func testGenerateToken() throws {
        let token = AuthService.generateLocalToken(userId: 42)
        #expect(!token.isEmpty)
        #expect(Data(base64Encoded: token) != nil)
    }

    @Test("parseLocalToken round-trips correctly")
    func testParseToken() throws {
        let token = AuthService.generateLocalToken(userId: 42)
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

    // MARK: - Active Users

    @Test("getActiveUsers returns only active users")
    func testGetActiveUsers() throws {
        let db = try freshDB()
        let auth = AuthService(db: db)
        _ = try auth.seedFirstAdmin(displayName: "Admin", pin: "1234")

        // Add an inactive user
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "INSERT INTO users (display_name, is_active) VALUES ('Inactive', 0)"
            )
        }

        let active = try auth.getActiveUsers()
        #expect(active.count == 1)
        #expect(active[0].displayName == "Admin")
    }
}
