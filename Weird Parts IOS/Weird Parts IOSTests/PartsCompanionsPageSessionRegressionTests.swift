import XCTest

final class PartsCompanionsPageSessionRegressionTests: XCTestCase {
    func testCompanionPollsDoNotFallBackToSyntheticUserZero() throws {
        let source = try Self.readPartsCompanionsPageSource()

        XCTAssertFalse(
            source.contains("appCore.currentUser?.id ?? 0"),
            "Companion polls must not substitute user id 0 for a missing session."
        )
        XCTAssertTrue(
            source.contains("private var currentUserId: Int64?"),
            "Companion polls should model the current user id as optional so missing-session state is explicit."
        )
        XCTAssertTrue(
            source.contains("guard let userId = currentUserId else"),
            "Companion poll loads should fail closed until a real current user id exists."
        )
        XCTAssertTrue(
            source.contains("loadError = \"User session unavailable. Sign in again.\""),
            "Companion polls should show a visible session error instead of loading vote state for user 0."
        )
        XCTAssertTrue(
            source.contains("try service.getActivePolls(userId: userId, isAdmin: isAdmin)")
                && source.contains("try service.getLastWeekResults(userId: userId)"),
            "Companion poll service calls should use the unwrapped real user id."
        )
        XCTAssertTrue(
            source.contains(".onChange(of: currentUserId)")
                && source.contains("reloadForCurrentUserChange()")
                && source.contains("await loadDataAndMarkViewed()"),
            "Companion polls should reload when the current user becomes available after initial page load."
        )
        XCTAssertTrue(
            source.contains("markCompanionsViewedIfReady()")
                && source.contains("currentUserId != nil")
                && source.contains("loadError == nil"),
            "Companion polls should not mark onboarding completed when the missing-session load fails closed."
        )
    }

    private static func readPartsCompanionsPageSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Parts")
            .appendingPathComponent("PartsCompanionsPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
