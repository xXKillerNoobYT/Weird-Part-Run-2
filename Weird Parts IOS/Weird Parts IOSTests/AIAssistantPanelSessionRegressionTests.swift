import XCTest

/// Regression coverage for issue #724: the AI assistant panel must never
/// substitute user id 0 for a missing session when invoking tool-backed chat.
/// With a nil user id, the core companion-poll and voting tools fail closed
/// with an explicit not-signed-in message instead of querying as user 0.
final class AIAssistantPanelSessionRegressionTests: XCTestCase {
    func testAssistantPanelDoesNotFallBackToSyntheticUserZero() throws {
        let source = try Self.readAssistantPanelSource()

        XCTAssertFalse(
            source.contains("appCore.currentUser?.id ?? 0"),
            "IOSAIAssistantPanel must not substitute user id 0 for a missing session — companion poll/voting tools would compute answers for user 0."
        )
        XCTAssertTrue(
            source.contains("userId: appCore.currentUser?.id,"),
            "IOSAIAssistantPanel should pass the optional current user id through to chatWithTools so core tools can fail closed when it is nil."
        )
    }

    private static func readAssistantPanelSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("AI")
            .appendingPathComponent("IOSAIAssistantPanel.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
