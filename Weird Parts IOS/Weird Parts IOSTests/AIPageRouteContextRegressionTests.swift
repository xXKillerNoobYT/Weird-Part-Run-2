import XCTest

/// Focused regression coverage for GitHub #86's router-owned context fallback.
/// These source-contract tests keep every AppTab covered without requiring
/// mutable backend fixtures or exposing business records to the assistant.
final class AIPageRouteContextRegressionTests: XCTestCase {
    func testRouterPublishesMinimalCurrentRouteAndLifecycleEvents() throws {
        let navigation = try Self.readSource("Navigation/NavigationConfig.swift")
        let router = try Self.readSource("Navigation/IOSContentRouter.swift")

        XCTAssertTrue(navigation.contains("WiredPart.routePageActive"))
        XCTAssertTrue(navigation.contains("WiredPart.routePageInactive"))
        XCTAssertTrue(navigation.contains("WiredPart.requestCurrentPageContext"))
        XCTAssertTrue(router.contains(".onAppear { postRouteContext() }"))
        XCTAssertTrue(router.contains(".onChange(of: path)"))
        XCTAssertTrue(router.contains("publisher(for: .requestCurrentPageContext)"))
        XCTAssertTrue(router.contains("name: .routePageInactive"))
        XCTAssertTrue(router.contains("guard let descriptor = routeDescriptor else { return }"))

        for allowedKey in ["\"context\"", "\"path\"", "\"pageId\"", "\"module\"", "\"page\""] {
            XCTAssertTrue(router.contains(allowedKey))
        }
        for forbiddenTerm in ["password", "token", "privateNotes", "mutationId", "rawDump"] {
            XCTAssertFalse(router.contains("\"\(forbiddenTerm)\":"))
        }
    }

    func testAssistantRequestsFreshRouteAndClearsItSafely() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")

        XCTAssertTrue(assistant.contains("post(name: .requestCurrentPageContext"))
        XCTAssertTrue(assistant.contains("publisher(for: .routePageActive)"))
        XCTAssertTrue(assistant.contains("publisher(for: .routePageInactive)"))
        XCTAssertTrue(assistant.contains("path == activeRoutePath"))
        XCTAssertTrue(assistant.contains("Current Route Context (READ-ONLY)"))

        let clear = try TestSourceSlicer.braceBalancedBody(
            after: "private func clearVolatilePageContext()",
            in: assistant
        )
        XCTAssertTrue(clear.contains("routeContext = nil"))
        XCTAssertTrue(clear.contains("activeRoutePath = nil"))
    }

    private static func readSource(_ relativePath: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
