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
            source.contains(".task(id: currentUserId)")
                && source.contains("await loadDataAndMarkViewed()"),
            "Companion polls should reload with SwiftUI task cancellation when the current user becomes available after initial page load."
        )
        XCTAssertTrue(
            source.contains("markCompanionsViewedIfReady()")
                && source.contains("currentUserId != nil")
                && source.contains("loadError == nil"),
            "Companion polls should not mark onboarding completed when the missing-session load fails closed."
        )
        XCTAssertTrue(
            source.contains("guard !Task.isCancelled, currentUserId != nil, loadError == nil else { return }"),
            "Companion polls should not mark onboarding completed if cancellation happens immediately before the mark."
        )
        XCTAssertTrue(
            source.contains("guard !Task.isCancelled else { return }"),
            "Companion poll loads should not publish stale state or mark onboarding after SwiftUI cancels an old user-id task."
        )
        let closeExpiredRange = try XCTUnwrap(source.range(of: "try service.closeExpiredPolls()"))
        let purgeExpiredRange = try XCTUnwrap(source.range(of: "try service.purgeExpiredRules()"))
        XCTAssertNotNil(
            source[..<closeExpiredRange.lowerBound].range(
                of: "guard !Task.isCancelled else { return }",
                options: .backwards
            ),
            "Companion poll housekeeping should check cancellation before closeExpiredPolls writes."
        )
        XCTAssertNotNil(
            source[closeExpiredRange.upperBound..<purgeExpiredRange.lowerBound].range(
                of: "guard !Task.isCancelled else { return }"
            ),
            "Companion poll housekeeping should check cancellation between closeExpiredPolls and purgeExpiredRules writes."
        )
        XCTAssertTrue(
            source.range(of: "guard let userId = currentUserId else")?.lowerBound ?? source.endIndex
                < source.range(of: "let rules = try service.listCompanionRulesHierarchy()")?.lowerBound ?? source.startIndex,
            "Companion loads should fail closed before doing unused service work when the user session is missing."
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
