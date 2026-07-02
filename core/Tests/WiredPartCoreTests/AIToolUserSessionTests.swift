import Foundation
import Testing
@testable import WiredPartCore

/// Regression coverage for issue #724: AI assistant companion-poll tools must
/// fail closed when no authenticated user exists, never defaulting to user 0.
@Suite("AIToolUserSession Tests")
struct AIToolUserSessionTests {

    // MARK: - validatedUserId (fail-closed rule, platform-independent)

    @Test("validatedUserId returns nil when no user session exists")
    func testValidatedUserId_nilSession() {
        #expect(AIToolUserSession.validatedUserId(nil) == nil)
    }

    @Test("validatedUserId rejects the legacy user-0 sentinel")
    func testValidatedUserId_zeroSentinel() {
        #expect(AIToolUserSession.validatedUserId(0) == nil)
    }

    @Test("validatedUserId rejects negative ids")
    func testValidatedUserId_negativeId() {
        #expect(AIToolUserSession.validatedUserId(-3) == nil)
    }

    @Test("validatedUserId passes through a real user id")
    func testValidatedUserId_realUser() {
        #expect(AIToolUserSession.validatedUserId(42) == 42)
    }

    @Test("notSignedInMessage tells the user to sign in again")
    func testNotSignedInMessage_isActionable() {
        #expect(AIToolUserSession.notSignedInMessage.lowercased().contains("sign in"))
    }

    // MARK: - Tool behavior (requires FoundationModels tool types)

    #if canImport(FoundationModels)
    @Test("GetActiveCompanionPollsTool fails closed when no user is signed in")
    func testActivePollsTool_failsClosedWithoutUser() async throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let env = try E2ETestHelpers.setUp()
        let tool = GetActiveCompanionPollsTool(
            db: env.db,
            permissions: ["view_parts_catalog"],
            userId: nil
        )
        let result = try await tool.call(arguments: .init())
        #expect(result == AIToolUserSession.notSignedInMessage)
    }

    @Test("GetActiveCompanionPollsTool fails closed for the user-0 sentinel")
    func testActivePollsTool_failsClosedForUserZero() async throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let env = try E2ETestHelpers.setUp()
        let tool = GetActiveCompanionPollsTool(
            db: env.db,
            permissions: ["view_parts_catalog"],
            userId: 0
        )
        let result = try await tool.call(arguments: .init())
        #expect(result == AIToolUserSession.notSignedInMessage)
    }

    @Test("GetActiveCompanionPollsTool still runs for a real signed-in user")
    func testActivePollsTool_runsForRealUser() async throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let env = try E2ETestHelpers.setUp()
        let tool = GetActiveCompanionPollsTool(
            db: env.db,
            permissions: ["view_parts_catalog"],
            userId: 1
        )
        let result = try await tool.call(arguments: .init())
        #expect(result != AIToolUserSession.notSignedInMessage)
    }

    @Test("GetVotingSummaryTool fails closed when no user is signed in")
    func testVotingSummaryTool_failsClosedWithoutUser() async throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let env = try E2ETestHelpers.setUp()
        let tool = GetVotingSummaryTool(
            db: env.db,
            permissions: ["view_parts_catalog"],
            userId: nil
        )
        let result = try await tool.call(arguments: .init())
        #expect(result == AIToolUserSession.notSignedInMessage)
    }

    @Test("GetVotingSummaryTool fails closed for the user-0 sentinel")
    func testVotingSummaryTool_failsClosedForUserZero() async throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let env = try E2ETestHelpers.setUp()
        let tool = GetVotingSummaryTool(
            db: env.db,
            permissions: ["view_parts_catalog"],
            userId: 0
        )
        let result = try await tool.call(arguments: .init())
        #expect(result == AIToolUserSession.notSignedInMessage)
    }

    @Test("GetVotingSummaryTool still runs for a real signed-in user")
    func testVotingSummaryTool_runsForRealUser() async throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let env = try E2ETestHelpers.setUp()
        let tool = GetVotingSummaryTool(
            db: env.db,
            permissions: ["view_parts_catalog"],
            userId: 1
        )
        let result = try await tool.call(arguments: .init())
        #expect(result != AIToolUserSession.notSignedInMessage)
    }

    @Test("permission check still precedes the session guard")
    func testTools_permissionDeniedBeforeSessionGuard() async throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let env = try E2ETestHelpers.setUp()
        let polls = GetActiveCompanionPollsTool(db: env.db, permissions: [], userId: nil)
        let voting = GetVotingSummaryTool(db: env.db, permissions: [], userId: nil)
        let pollsResult = try await polls.call(arguments: .init())
        let votingResult = try await voting.call(arguments: .init())
        #expect(pollsResult == "You don't have permission to view companion polls.")
        #expect(votingResult == "You don't have permission to view voting data.")
    }
    #endif
}
