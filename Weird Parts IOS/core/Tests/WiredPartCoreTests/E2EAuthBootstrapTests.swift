import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// End-to-end tests for the full authentication and bootstrap lifecycle.
///
/// Covers: first-run bootstrap → login → session management → permissions → logout.
@Suite("E2E: Auth & Bootstrap")
struct E2EAuthBootstrapTests {

    // MARK: - Full Bootstrap Flow

    @Test("Complete first-run bootstrap creates working environment")
    func testBootstrapCreatesFullEnvironment() throws {
        let env = try E2ETestHelpers.setUp()

        // Admin user exists and is active
        let users = try env.auth.getActiveUsers()
        #expect(users.count == 1)
        #expect(users[0].displayName == "TestAdmin")

        // 7 hats were created
        let hatCount = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hats")!
        }
        #expect(hatCount == 7)

        // Permissions were assigned
        let perms = try env.auth.getUserPermissions(env.adminUserId)
        #expect(perms.count > 30) // Admin has 40+ permissions

        // Default settings were created
        let companyName = try env.settings.getSettingValue("company_name")
        #expect(companyName == "TestAdmin's Company")

        // Activity log records the bootstrap
        let logCount = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM activity_log WHERE action = 'first_admin_setup'")!
        }
        #expect(logCount == 1)
    }

    @Test("Bootstrap prevents double-seeding")
    func testBootstrapPreventsDoubleSeed() throws {
        let env = try E2ETestHelpers.setUp()
        let secondResult = try env.auth.seedFirstAdmin(displayName: "SecondAdmin", pin: "5678")
        #expect(!secondResult.success)
    }

    // MARK: - Login Flow

    @Test("Login with correct PIN returns valid session")
    func testLoginSuccess() throws {
        let env = try E2ETestHelpers.setUp()
        let result = try env.auth.authenticateByPin(userId: env.adminUserId, pin: "1234")

        #expect(result.success)
        #expect(result.user?.id == env.adminUserId)
        #expect(result.token != nil)

        // Token is valid and can be used to get profile
        let profile = try env.auth.getLocalUserProfile(token: result.token!)
        #expect(profile.displayName == "TestAdmin")
        #expect(profile.isActive)
        #expect(!profile.permissions.isEmpty)
    }

    @Test("Login with wrong PIN fails")
    func testLoginWrongPin() throws {
        let env = try E2ETestHelpers.setUp()
        let result = try env.auth.authenticateByPin(userId: env.adminUserId, pin: "0000")
        #expect(!result.success)
        #expect(result.message == "Invalid PIN")
    }

    @Test("Login with non-existent user fails")
    func testLoginNonexistentUser() throws {
        let env = try E2ETestHelpers.setUp()
        let result = try env.auth.authenticateByPin(userId: 9999, pin: "1234")
        #expect(!result.success)
    }

    // MARK: - Permission System

    @Test("Admin has all core permissions")
    func testAdminCorePermissions() throws {
        let env = try E2ETestHelpers.setUp()
        let perms = try env.auth.getUserPermissions(env.adminUserId)

        let required = [
            "view_parts_catalog", "edit_parts_catalog", "manage_settings",
            "manage_devices", "view_jobs", "manage_jobs", "view_warehouse",
            "manage_warehouse", "view_orders", "manage_orders", "view_people",
            "manage_people", "view_fleet", "manage_fleet", "view_tools",
            "manage_tools", "view_scheduling", "manage_scheduling",
            "use_chat", "view_chat", "manage_chat",
        ]
        for perm in required {
            #expect(perms.contains(perm), "Missing permission: \(perm)")
        }
    }

    @Test("hasPermission correctly checks individual permissions")
    func testHasPermission() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(try env.auth.hasPermission(env.adminUserId, permissionKey: "manage_settings"))
        #expect(try !env.auth.hasPermission(env.adminUserId, permissionKey: "nonexistent_perm"))
    }

    // MARK: - User Profile

    @Test("Full user profile includes hats and permissions")
    func testUserProfile() throws {
        let env = try E2ETestHelpers.setUp()
        let profile = try env.auth.getLocalUserProfile(token: env.adminToken)

        #expect(profile.id == env.adminUserId)
        #expect(profile.displayName == "TestAdmin")
        #expect(profile.isActive)
        #expect(!profile.hats.isEmpty)
        #expect(profile.hats[0].name == "Admin")
        #expect(profile.hats[0].level == 100)
        #expect(!profile.permissions.isEmpty)
    }

    @Test("Invalid token throws error")
    func testInvalidToken() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: AuthService.AuthError.self) {
            _ = try env.auth.getLocalUserProfile(token: "garbage")
        }
    }

    // MARK: - Hat System

    @Test("Admin hat names are correct")
    func testHatNames() throws {
        let env = try E2ETestHelpers.setUp()
        let hatNames = try env.auth.getUserHatNames(env.adminUserId)
        #expect(hatNames.contains("Admin"))
    }

    @Test("Hat summaries include level hierarchy")
    func testHatSummaries() throws {
        let env = try E2ETestHelpers.setUp()
        let hats = try env.auth.getUserHats(env.adminUserId)
        #expect(!hats.isEmpty)
        #expect(hats[0].name == "Admin")
        #expect(hats[0].level == 100)
    }
}
