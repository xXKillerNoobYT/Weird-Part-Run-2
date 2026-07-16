import XCTest
@testable import Weird_Parts

final class TabBarEditorRegressionTests: XCTestCase {
    @MainActor
    func testFourVisibleModuleFixtureHasNoMoreDestinationOrFastDemoteActions() {
        let visibleIds = ["dashboard", "jobs", "chat", "scheduling"]
        let layout = TabBarEditorLayout(orderedIds: visibleIds)

        XCTAssertEqual(layout.bottomIds, visibleIds)
        XCTAssertTrue(layout.moreIds.isEmpty)
        XCTAssertFalse(
            layout.hasMoreDestination,
            "A four-visible-module permission fixture must not expose a More divider or destination."
        )
        XCTAssertFalse(
            layout.exportsFastDemoteActions,
            "Fast rows must not export enabled 'Move … to More menu' actions when the More destination is absent."
        )
    }

    @MainActor
    func testFiveVisibleModuleFixtureKeepsMoreDestinationAndDemoteActions() {
        let visibleIds = ["dashboard", "jobs", "chat", "scheduling", "warehouse"]
        let layout = TabBarEditorLayout(orderedIds: visibleIds)

        XCTAssertEqual(layout.bottomIds, ["dashboard", "jobs", "chat", "scheduling"])
        XCTAssertEqual(layout.moreIds, ["warehouse"])
        XCTAssertTrue(layout.hasMoreDestination)
        XCTAssertTrue(layout.exportsFastDemoteActions)
    }

    func testSourceKeepsMoreDividerAndFastDemoteButtonBehindDestinationCheck() throws {
        let source = try Self.readTabBarEditorSource()

        XCTAssertTrue(
            source.contains("if !moreIds.isEmpty {\n            items.append(.moreDivider)"),
            "The More divider must stay absent for four-or-fewer visible modules."
        )
        XCTAssertTrue(
            source.contains("if !isFastAccess || hasMoreDestination {"),
            "Fast-row demote buttons must only be exported when a real More destination exists."
        )
        XCTAssertTrue(source.contains("\"Move \\(module.label) to More menu\""))
    }

    private static func readTabBarEditorSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Navigation")
            .appendingPathComponent("TabBarEditorView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
