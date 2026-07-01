import XCTest

final class FlexPoolPageSessionRegressionTests: XCTestCase {
    func testFlexPoolDoesNotFallBackToSyntheticUserZero() throws {
        let source = try Self.readFlexPoolPageSource()

        XCTAssertFalse(
            source.contains("appCore.currentUser?.id ?? 0"),
            "Flex Pool must not substitute user id 0 for a missing session."
        )
        XCTAssertTrue(
            source.contains("private var currentUserId: Int64?"),
            "Flex Pool should model the current user id as optional so missing-session state is explicit."
        )
        XCTAssertTrue(
            source.contains("guard let userId = currentUserId else"),
            "Flex Pool fetch and claim flows should fail closed until a real current user id exists."
        )
        XCTAssertTrue(
            source.contains("loadError = \"User session unavailable. Sign in again.\""),
            "Flex Pool should show a visible session error instead of loading jobs for user 0."
        )
        XCTAssertTrue(
            source.contains("claimError = \"User session unavailable. Sign in again.\""),
            "Flex Pool claim attempts should surface a session error instead of calling claimFlexJob with user 0."
        )
        XCTAssertTrue(
            source.contains("try service.fetchFlexPool(userId: userId)")
                && source.contains("try service.claimFlexJob(jobId: job.id, userId: userId)"),
            "Flex Pool service calls should use the unwrapped real user id."
        )
    }

    private static func readFlexPoolPageSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Scheduling")
            .appendingPathComponent("IOSFlexPoolPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
